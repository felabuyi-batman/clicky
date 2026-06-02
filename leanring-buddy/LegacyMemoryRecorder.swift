//
//  LegacyMemoryRecorder.swift
//  leanring-buddy
//
//  Records a single spoken memory answer to a WAV file (used both for playback
//  and as voice-cloning material) and transcribes it locally with Apple's
//  Speech framework. Self-contained and separate from the push-to-talk
//  dictation pipeline so the interview can record full, unhurried answers.
//

import AVFoundation
import Foundation
import Speech

@MainActor
final class LegacyMemoryRecorder: NSObject, ObservableObject {

    /// True while audio is actively being recorded.
    @Published private(set) var isRecording = false

    /// Live microphone power level (0...1) for a simple waveform/meter in the UI.
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0

    /// Seconds elapsed in the current recording, for an on-screen timer.
    @Published private(set) var elapsedRecordingSeconds: Double = 0

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var recordingStartDate: Date?
    private var activeRecordingFileURL: URL?

    /// The result of finishing a recording: where the audio landed, how long it
    /// was, and the transcribed text.
    struct RecordedMemoryResult {
        let audioFileURL: URL
        let durationSeconds: Double
        let transcript: String
    }

    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case speechPermissionDenied
        case recordingFailed(message: String)
        case transcriptionFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access is needed to record memories."
            case .speechPermissionDenied:
                return "Speech recognition access is needed to transcribe memories."
            case .recordingFailed(let message):
                return "Recording failed: \(message)"
            case .transcriptionFailed(let message):
                return "Couldn't transcribe that recording: \(message)"
            }
        }
    }

    // MARK: - Recording

    /// Begins recording to a new WAV file inside `directory`. Throws if mic
    /// permission is denied or the recorder can't start.
    func startRecording(intoDirectory directory: URL) async throws {
        guard !isRecording else { return }

        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            throw RecorderError.microphonePermissionDenied
        }

        let fileName = "memory-\(UUID().uuidString).wav"
        let fileURL = directory.appendingPathComponent(fileName)

        // Linear PCM WAV at 44.1kHz mono — broadly compatible and good enough
        // quality for both playback and ElevenLabs voice cloning.
        let recorderSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: recorderSettings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw RecorderError.recordingFailed(message: "The recorder refused to start.")
            }
            self.audioRecorder = recorder
            self.activeRecordingFileURL = fileURL
            self.recordingStartDate = Date()
            self.isRecording = true
            self.elapsedRecordingSeconds = 0
            startMetering()
        } catch let recorderError as RecorderError {
            throw recorderError
        } catch {
            throw RecorderError.recordingFailed(message: error.localizedDescription)
        }
    }

    /// Stops recording, transcribes the captured audio, and returns the result.
    /// The caller is responsible for turning this into a LegacyMemory and saving it.
    func stopRecordingAndTranscribe() async throws -> RecordedMemoryResult {
        guard let recorder = audioRecorder, let fileURL = activeRecordingFileURL else {
            throw RecorderError.recordingFailed(message: "There was no active recording.")
        }

        let durationSeconds = recorder.currentTime
        recorder.stop()
        stopMetering()
        isRecording = false
        audioRecorder = nil
        activeRecordingFileURL = nil
        recordingStartDate = nil

        let speechGranted = await requestSpeechRecognitionPermission()
        guard speechGranted else {
            throw RecorderError.speechPermissionDenied
        }

        let transcript = try await transcribeAudioFile(at: fileURL)

        return RecordedMemoryResult(
            audioFileURL: fileURL,
            durationSeconds: durationSeconds,
            transcript: transcript
        )
    }

    /// Cancels and discards the current recording without transcribing.
    func cancelRecording() {
        audioRecorder?.stop()
        if let fileURL = activeRecordingFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        stopMetering()
        isRecording = false
        audioRecorder = nil
        activeRecordingFileURL = nil
        recordingStartDate = nil
        currentAudioPowerLevel = 0
        elapsedRecordingSeconds = 0
    }

    // MARK: - Metering

    private func startMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeters()
            }
        }
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        currentAudioPowerLevel = 0
    }

    private func updateMeters() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()

        // averagePower is in decibels (-160 silence ... 0 loudest). Map it to a
        // 0...1 range for the UI meter with a simple normalized curve.
        let averagePowerDecibels = recorder.averagePower(forChannel: 0)
        let normalizedLevel = pow(10.0, averagePowerDecibels / 20.0)
        currentAudioPowerLevel = CGFloat(min(max(normalizedLevel, 0), 1))

        if let startDate = recordingStartDate {
            elapsedRecordingSeconds = Date().timeIntervalSince(startDate)
        }
    }

    // MARK: - Transcription

    private func transcribeAudioFile(at fileURL: URL) async throws -> String {
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer() else {
            throw RecorderError.transcriptionFailed(message: "Speech recognition isn't available on this Mac.")
        }

        // Prefer on-device recognition when supported so long memories aren't
        // capped by the server-side dictation time limit.
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: fileURL)
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            speechRecognizer.recognitionTask(with: recognitionRequest) { recognitionResult, error in
                if let error {
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: RecorderError.transcriptionFailed(message: error.localizedDescription))
                    }
                    return
                }

                guard let recognitionResult else { return }
                if recognitionResult.isFinal && !hasResumed {
                    hasResumed = true
                    let transcript = recognitionResult.bestTranscription.formattedString
                    continuation.resume(returning: transcript)
                }
            }
        }
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            default:
                continuation.resume(returning: false)
            }
        }
    }

    private func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                    continuation.resume(returning: authorizationStatus == .authorized)
                }
            default:
                continuation.resume(returning: false)
            }
        }
    }
}
