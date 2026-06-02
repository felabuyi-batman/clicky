//
//  LegacyPersonaConversationManager.swift
//  leanring-buddy
//
//  Drives a back-and-forth conversation with a preserved persona. Sends the
//  user's message (plus the persona-grounded system prompt and prior turns) to
//  Claude, streams the reply for progressive display, and optionally speaks the
//  reply aloud in the persona's cloned voice via ElevenLabs.
//

import Foundation

/// One line in the persona conversation transcript, used to render the chat UI
/// and to feed prior turns back to Claude for context.
struct LegacyConversationTurn: Identifiable, Hashable {
    enum Speaker {
        case family   // the living person talking to the persona
        case persona  // the preserved person replying
    }

    let id = UUID()
    let speaker: Speaker
    var text: String
}

@MainActor
final class LegacyPersonaConversationManager: ObservableObject {

    /// The full visible transcript of the current conversation.
    @Published private(set) var conversationTurns: [LegacyConversationTurn] = []

    /// True while a reply is being generated, so the UI can show a thinking state
    /// and disable sending another message.
    @Published private(set) var isGeneratingReply = false

    /// Set when the most recent send failed, for surfacing an error in the UI.
    @Published private(set) var lastErrorMessage: String?

    private let claudeAPI: ClaudeAPI
    private let elevenLabsTTSClient: ElevenLabsTTSClient
    private let memoryStore: LegacyMemoryStore

    /// When true, replies are spoken aloud in the persona's cloned voice.
    var shouldSpeakRepliesAloud: Bool = true

    init(
        claudeAPI: ClaudeAPI,
        elevenLabsTTSClient: ElevenLabsTTSClient,
        memoryStore: LegacyMemoryStore
    ) {
        self.claudeAPI = claudeAPI
        self.elevenLabsTTSClient = elevenLabsTTSClient
        self.memoryStore = memoryStore
    }

    /// Clears the transcript so a fresh conversation can begin.
    func startNewConversation() {
        conversationTurns = []
        lastErrorMessage = nil
    }

    /// Sends a message from the living family member to the persona, streams the
    /// reply into the transcript, and speaks it aloud if enabled.
    func sendMessage(_ familyMessage: String) async {
        let trimmedMessage = familyMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, !isGeneratingReply else { return }

        lastErrorMessage = nil
        isGeneratingReply = true

        conversationTurns.append(
            LegacyConversationTurn(speaker: .family, text: trimmedMessage)
        )

        // Insert an empty persona turn we stream tokens into as they arrive.
        let personaTurnIndex = conversationTurns.count
        conversationTurns.append(
            LegacyConversationTurn(speaker: .persona, text: "")
        )

        let systemPrompt = LegacyPersonaPromptBuilder.systemPrompt(
            for: memoryStore.persona,
            memories: memoryStore.capturedMemories
        )

        // Build prior turns (excluding the two we just appended) as
        // (user, assistant) pairs for Claude's context window.
        let priorConversationHistory = buildPriorConversationHistory(excludingLastTwoTurns: true)

        do {
            let result = try await claudeAPI.streamTextConversation(
                systemPrompt: systemPrompt,
                conversationHistory: priorConversationHistory,
                userMessage: trimmedMessage,
                onTextChunk: { [weak self] accumulatedReply in
                    guard let self else { return }
                    guard self.conversationTurns.indices.contains(personaTurnIndex) else { return }
                    self.conversationTurns[personaTurnIndex].text = accumulatedReply
                }
            )

            if shouldSpeakRepliesAloud {
                await speakReplyAloud(result.text)
            }
        } catch is CancellationError {
            // Silently ignore — a new send cancelled this one.
        } catch {
            lastErrorMessage = error.localizedDescription
            // Drop the empty/partial persona turn so the UI doesn't show a blank bubble.
            if conversationTurns.indices.contains(personaTurnIndex),
               conversationTurns[personaTurnIndex].text.isEmpty {
                conversationTurns.remove(at: personaTurnIndex)
            }
        }

        isGeneratingReply = false
    }

    /// Speaks the persona's reply in its cloned voice when one exists, falling
    /// back to the default voice while a clone hasn't been created yet.
    private func speakReplyAloud(_ replyText: String) async {
        let trimmedReply = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else { return }

        let clonedVoiceID = memoryStore.persona.clonedVoiceID
        do {
            try await elevenLabsTTSClient.speakText(trimmedReply, voiceID: clonedVoiceID)
        } catch {
            print("⚠️ LegacyPersonaConversationManager: failed to speak reply: \(error)")
        }
    }

    /// Converts the visible transcript into (user, assistant) pairs for Claude.
    /// Family messages map to "user" turns and persona replies to "assistant"
    /// turns. Optionally drops the final two turns (the in-flight exchange) so
    /// the new user message isn't duplicated.
    private func buildPriorConversationHistory(
        excludingLastTwoTurns: Bool
    ) -> [(userMessage: String, assistantResponse: String)] {
        var turnsToConsider = conversationTurns
        if excludingLastTwoTurns && turnsToConsider.count >= 2 {
            turnsToConsider.removeLast(2)
        }

        var pairedHistory: [(userMessage: String, assistantResponse: String)] = []
        var pendingFamilyMessage: String?

        for turn in turnsToConsider {
            switch turn.speaker {
            case .family:
                pendingFamilyMessage = turn.text
            case .persona:
                if let familyMessage = pendingFamilyMessage {
                    pairedHistory.append((userMessage: familyMessage, assistantResponse: turn.text))
                    pendingFamilyMessage = nil
                }
            }
        }

        return pairedHistory
    }
}
