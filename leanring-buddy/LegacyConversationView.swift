//
//  LegacyConversationView.swift
//  leanring-buddy
//
//  The "talk to the memory" screen. Shows the conversation transcript with the
//  preserved persona and lets the user type a message; replies stream in and
//  are spoken aloud in the persona's cloned voice when one exists.
//

import SwiftUI

struct LegacyConversationView: View {
    @ObservedObject var legacyManager: LegacyManager
    @ObservedObject var conversationManager: LegacyPersonaConversationManager

    /// Records a spoken message in the Talk tab so the user can have a fully
    /// voice-to-voice conversation: speak a question, hear the persona answer in
    /// their cloned voice. Audio is transcribed then discarded (it is not kept
    /// as a memory).
    @StateObject private var voiceInputRecorder = LegacyMemoryRecorder()

    @State private var messageInput: String = ""
    @State private var shouldSpeakRepliesAloud: Bool = true
    @State private var isTranscribingVoiceInput = false
    @State private var voiceInputErrorMessage: String?

    init(legacyManager: LegacyManager) {
        self.legacyManager = legacyManager
        self.conversationManager = legacyManager.conversationManager
    }

    var body: some View {
        VStack(spacing: 0) {
            if legacyManager.isPersonaReadyForConversation {
                conversationHeader
                transcriptScrollView
                inputBar
            } else {
                notReadyState
            }
        }
    }

    // MARK: - Header

    private var conversationHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(legacyManager.memoryStore.persona.hasClonedVoice ? DS.Colors.success : DS.Colors.textTertiary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(legacyManager.memoryStore.persona.ownerDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(legacyManager.memoryStore.persona.hasClonedVoice ? "Speaking in their cloned voice" : "Using a stand-in voice")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $shouldSpeakRepliesAloud)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: shouldSpeakRepliesAloud) { _, newValue in
                    conversationManager.shouldSpeakRepliesAloud = newValue
                }
                .help("Speak replies aloud")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Transcript

    private var transcriptScrollView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(conversationManager.conversationTurns) { conversationTurn in
                        conversationBubble(conversationTurn)
                            .id(conversationTurn.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: conversationManager.conversationTurns.count) { _, _ in
                if let lastTurnID = conversationManager.conversationTurns.last?.id {
                    withAnimation { scrollProxy.scrollTo(lastTurnID, anchor: .bottom) }
                }
            }
        }
    }

    private func conversationBubble(_ conversationTurn: LegacyConversationTurn) -> some View {
        let isFromFamily = conversationTurn.speaker == .family
        return HStack {
            if isFromFamily { Spacer(minLength: 40) }

            Text(conversationTurn.text.isEmpty ? "…" : conversationTurn.text)
                .font(.system(size: 13))
                .foregroundColor(isFromFamily ? .white : DS.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                        .fill(isFromFamily ? DS.Colors.blue500 : DS.Colors.surface2)
                )
                .frame(maxWidth: 320, alignment: isFromFamily ? .trailing : .leading)

            if !isFromFamily { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isFromFamily ? .trailing : .leading)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 8) {
            if voiceInputRecorder.isRecording || isTranscribingVoiceInput || voiceInputErrorMessage != nil {
                voiceInputStatusRow
            }

            HStack(spacing: 10) {
                voiceInputButton

                TextField("Say something to them…", text: $messageInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                            .fill(DS.Colors.surface1)
                    )
                    .disabled(voiceInputRecorder.isRecording || isTranscribingVoiceInput)
                    .onSubmit { sendCurrentMessage() }

                Button(action: { sendCurrentMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSendMessage ? DS.Colors.blue500 : DS.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(!canSendMessage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// The hold-free mic button: tap to start speaking, tap again to send. While
    /// the persona is replying the button is disabled so turns don't overlap.
    private var voiceInputButton: some View {
        Button(action: { toggleVoiceInput() }) {
            Image(systemName: voiceInputRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(voiceInputButtonColor)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(isTranscribingVoiceInput || conversationManager.isGeneratingReply)
        .help(voiceInputRecorder.isRecording ? "Stop and send" : "Speak your message")
    }

    private var voiceInputButtonColor: Color {
        if voiceInputRecorder.isRecording { return Color.red.opacity(0.9) }
        if isTranscribingVoiceInput || conversationManager.isGeneratingReply { return DS.Colors.textTertiary }
        return DS.Colors.blue500
    }

    /// The live status shown above the input bar while speaking, transcribing, or
    /// after a voice-input error.
    private var voiceInputStatusRow: some View {
        HStack(spacing: 10) {
            if voiceInputRecorder.isRecording {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 8, height: 8)
                Text("Listening…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                RoundedRectangle(cornerRadius: DS.CornerRadius.pill, style: .continuous)
                    .fill(DS.Colors.blue400)
                    .frame(width: max(8, 70 * voiceInputRecorder.currentAudioPowerLevel), height: 6)
                    .animation(.linear(duration: 0.05), value: voiceInputRecorder.currentAudioPowerLevel)
                Text(formattedVoiceInputElapsedTime)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(DS.Colors.textTertiary)
            } else if isTranscribingVoiceInput {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textTertiary)
            } else if let voiceInputErrorMessage {
                Text(voiceInputErrorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var formattedVoiceInputElapsedTime: String {
        let totalSeconds = Int(voiceInputRecorder.elapsedRecordingSeconds)
        return String(format: "%01d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var canSendMessage: Bool {
        !messageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !conversationManager.isGeneratingReply
    }

    private func sendCurrentMessage() {
        guard canSendMessage else { return }
        let messageToSend = messageInput
        messageInput = ""
        conversationManager.shouldSpeakRepliesAloud = shouldSpeakRepliesAloud
        Task {
            await conversationManager.sendMessage(messageToSend)
        }
    }

    // MARK: - Voice input (push-to-talk in Talk mode)

    private func toggleVoiceInput() {
        if voiceInputRecorder.isRecording {
            Task { await finishVoiceInputAndSend() }
        } else {
            Task { await startVoiceInput() }
        }
    }

    private func startVoiceInput() async {
        voiceInputErrorMessage = nil
        do {
            // Record into the system temp directory — this audio is only used to
            // transcribe the spoken message and is deleted right after.
            try await voiceInputRecorder.startRecording(intoDirectory: FileManager.default.temporaryDirectory)
        } catch {
            voiceInputErrorMessage = error.localizedDescription
        }
    }

    private func finishVoiceInputAndSend() async {
        isTranscribingVoiceInput = true
        defer { isTranscribingVoiceInput = false }

        do {
            let recordingResult = try await voiceInputRecorder.stopRecordingAndTranscribe()
            // Voice input in the conversation is transient; discard the audio file.
            try? FileManager.default.removeItem(at: recordingResult.audioFileURL)

            let spokenMessage = recordingResult.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spokenMessage.isEmpty else {
                voiceInputErrorMessage = "I didn't catch that — tap the mic and try again."
                return
            }

            conversationManager.shouldSpeakRepliesAloud = shouldSpeakRepliesAloud
            await conversationManager.sendMessage(spokenMessage)
        } catch {
            voiceInputErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Not ready

    private var notReadyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28))
                .foregroundColor(DS.Colors.textTertiary)
            Text("This memory isn't ready to talk yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text("Add a name, record a few memories, and build the biography first.")
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
