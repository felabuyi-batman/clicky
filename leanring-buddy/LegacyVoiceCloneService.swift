//
//  LegacyVoiceCloneService.swift
//  leanring-buddy
//
//  Uploads the user's recorded memory audio to the Cloudflare Worker, which
//  forwards it to ElevenLabs instant voice cloning and returns a voice id. That
//  voice id is then stored on the LegacyPersona and used so the AI replies in
//  the person's own cloned voice.
//

import Foundation

@MainActor
final class LegacyVoiceCloneService {

    private let voiceCloneProxyURL: URL
    private let session: URLSession

    init(proxyURL: String) {
        self.voiceCloneProxyURL = URL(string: proxyURL)!

        let configuration = URLSessionConfiguration.default
        // Voice cloning uploads several audio files, so allow a generous timeout.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }

    /// Errors surfaced to the UI when cloning can't proceed or fails upstream.
    enum VoiceCloneError: LocalizedError {
        case noAudioRecordings
        case serverError(message: String)
        case missingVoiceID

        var errorDescription: String? {
            switch self {
            case .noAudioRecordings:
                return "Record a few memories out loud first — there's no voice audio to clone yet."
            case .serverError(let message):
                return "Voice cloning failed: \(message)"
            case .missingVoiceID:
                return "Voice cloning succeeded but no voice id was returned."
            }
        }
    }

    /// Clones a voice from the given local audio files. `voiceName` becomes the
    /// ElevenLabs voice label (e.g. the person's name). Returns the new voice id.
    func cloneVoice(
        named voiceName: String,
        fromAudioFileURLs audioFileURLs: [URL]
    ) async throws -> String {
        guard !audioFileURLs.isEmpty else {
            throw VoiceCloneError.noAudioRecordings
        }

        let multipartBoundary = "Boundary-\(UUID().uuidString)"
        let multipartBody = try buildMultipartBody(
            voiceName: voiceName,
            audioFileURLs: audioFileURLs,
            boundary: multipartBoundary
        )

        var request = URLRequest(url: voiceCloneProxyURL)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(multipartBoundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = multipartBody

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw VoiceCloneError.serverError(message: errorMessage)
        }

        guard let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let clonedVoiceID = responseJSON["voice_id"] as? String,
              !clonedVoiceID.isEmpty else {
            throw VoiceCloneError.missingVoiceID
        }

        return clonedVoiceID
    }

    /// Assembles a multipart/form-data body with the voice name and each audio
    /// file. ElevenLabs' add-voice endpoint reads the `name` field and one or
    /// more `files` parts.
    private func buildMultipartBody(
        voiceName: String,
        audioFileURLs: [URL],
        boundary: String
    ) throws -> Data {
        var body = Data()

        func appendString(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        // The voice name field.
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"name\"\r\n\r\n")
        appendString("\(voiceName)\r\n")

        // Each recorded answer as a "files" part.
        for audioFileURL in audioFileURLs {
            let audioData = try Data(contentsOf: audioFileURL)
            let fileName = audioFileURL.lastPathComponent
            appendString("--\(boundary)\r\n")
            appendString("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n")
            appendString("Content-Type: audio/wav\r\n\r\n")
            body.append(audioData)
            appendString("\r\n")
        }

        appendString("--\(boundary)--\r\n")
        return body
    }
}
