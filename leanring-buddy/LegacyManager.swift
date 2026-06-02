//
//  LegacyManager.swift
//  leanring-buddy
//
//  Coordinator for the "digital immortality" feature. Owns the memory store and
//  all the legacy services, and exposes high-level operations the UI calls:
//  generating a biography from captured memories, cloning the user's voice, and
//  syncing the persona to the backend. The conversation itself is driven by the
//  LegacyPersonaConversationManager exposed here.
//

import Foundation
import Combine

@MainActor
final class LegacyManager: ObservableObject {

    /// The persisted memory library and persona. Published so the UI updates as
    /// memories are captured.
    let memoryStore: LegacyMemoryStore

    /// Drives the chat-with-persona conversation.
    let conversationManager: LegacyPersonaConversationManager

    /// True while a long-running operation (voice clone or biography build) runs,
    /// so the UI can show progress and disable re-triggering.
    @Published private(set) var isCloningVoice = false
    @Published private(set) var isBuildingBiography = false
    @Published private(set) var lastErrorMessage: String?

    /// Where the persona stands relative to the backend, so the UI can show that
    /// the consciousness is safely backed up (and never only on one device).
    enum PersonaSyncState: Equatable {
        case idle
        case syncing
        case synced
        case failed(message: String)
    }
    @Published private(set) var personaSyncState: PersonaSyncState = .idle

    private let claudeAPI: ClaudeAPI
    private let elevenLabsTTSClient: ElevenLabsTTSClient
    private let voiceCloneService: LegacyVoiceCloneService
    private let personaSyncService: LegacyPersonaSyncService

    /// Keeps the auto-sync subscription alive for the life of the manager.
    private var personaChangeCancellable: AnyCancellable?

    /// ElevenLabs instant cloning works with a fairly small amount of clean
    /// speech; we ask the user to record at least this much before enabling the
    /// "clone my voice" action so the result is recognizable.
    static let minimumRecordedSecondsForCloning: Double = 60

    init(workerBaseURL: String) {
        let memoryStore = LegacyMemoryStore()
        let claudeAPI = ClaudeAPI(proxyURL: "\(workerBaseURL)/chat")
        let elevenLabsTTSClient = ElevenLabsTTSClient(proxyURL: "\(workerBaseURL)/tts")

        self.memoryStore = memoryStore
        self.claudeAPI = claudeAPI
        self.elevenLabsTTSClient = elevenLabsTTSClient
        self.voiceCloneService = LegacyVoiceCloneService(proxyURL: "\(workerBaseURL)/voice-clone")
        self.personaSyncService = LegacyPersonaSyncService(personaSyncBaseURL: "\(workerBaseURL)/persona")
        self.conversationManager = LegacyPersonaConversationManager(
            claudeAPI: claudeAPI,
            elevenLabsTTSClient: elevenLabsTTSClient,
            memoryStore: memoryStore
        )

        startAutoSyncingPersonaOnChange()
    }

    /// Watches the persona for changes and pushes it to the backend automatically,
    /// debounced so a flurry of edits (typing a name, building a biography) results
    /// in a single upload once things settle. Skips empty personas so we don't sync
    /// a blank record on first launch.
    private func startAutoSyncingPersonaOnChange() {
        personaChangeCancellable = memoryStore.$persona
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] changedPersona in
                guard let self else { return }
                guard !changedPersona.ownerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                Task { await self.syncPersonaToBackend() }
            }
    }

    /// Whether enough audio has been recorded to attempt voice cloning.
    var hasEnoughAudioToCloneVoice: Bool {
        memoryStore.totalRecordedAudioSeconds >= Self.minimumRecordedSecondsForCloning
    }

    /// Updates the name of the person being preserved.
    func updateOwnerDisplayName(_ newName: String) {
        var updatedPersona = memoryStore.persona
        updatedPersona.ownerDisplayName = newName
        memoryStore.updatePersona(updatedPersona)
    }

    /// Saves a freshly recorded answer as a memory in the library.
    func saveRecordedMemory(
        forPrompt prompt: LegacyMemoryPrompt,
        recordingResult: LegacyMemoryRecorder.RecordedMemoryResult
    ) {
        let capturedMemory = LegacyMemory(
            promptID: prompt.id,
            promptQuestion: prompt.questionText,
            category: prompt.category,
            transcript: recordingResult.transcript,
            audioFileName: recordingResult.audioFileURL.lastPathComponent,
            recordedDurationSeconds: recordingResult.durationSeconds
        )
        memoryStore.addMemory(capturedMemory)
    }

    /// Whether the persona is ready to talk to: it has a name, at least one
    /// memory, and a generated biography.
    var isPersonaReadyForConversation: Bool {
        !memoryStore.persona.ownerDisplayName.isEmpty
            && !memoryStore.capturedMemories.isEmpty
            && !memoryStore.persona.biography.isEmpty
    }

    // MARK: - Biography

    /// Asks Claude to distill the captured memories into a warm first-person
    /// biography, then stores it on the persona. This biography grounds the
    /// conversation so the AI speaks as the real person.
    func buildBiographyFromMemories() async {
        guard !isBuildingBiography else { return }
        guard !memoryStore.capturedMemories.isEmpty else {
            lastErrorMessage = "Record at least one memory before building the biography."
            return
        }

        isBuildingBiography = true
        lastErrorMessage = nil

        let personName = memoryStore.persona.ownerDisplayName.isEmpty
            ? "this person"
            : memoryStore.persona.ownerDisplayName

        let renderedMemories = memoryStore.capturedMemories
            .map { memory in "Q: \(memory.promptQuestion)\nA: \(memory.transcript)" }
            .joined(separator: "\n\n")

        let systemPrompt = """
            You are helping preserve a person's life story. From the question-and-answer memories below, \
            write a warm, first-person biography of \(personName) — the way they would describe themselves. \
            Capture their personality, the people they love, and the moments that shaped them. Use only what \
            the memories contain; do not invent facts. Write 2-4 short paragraphs in the first person.
            """

        do {
            let result = try await claudeAPI.streamTextConversation(
                systemPrompt: systemPrompt,
                conversationHistory: [],
                userMessage: "Here are my memories:\n\n\(renderedMemories)",
                onTextChunk: { _ in }
            )

            var updatedPersona = memoryStore.persona
            updatedPersona.biography = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            memoryStore.updatePersona(updatedPersona)
        } catch {
            lastErrorMessage = "Couldn't build the biography: \(error.localizedDescription)"
        }

        isBuildingBiography = false
    }

    // MARK: - Voice cloning

    /// Clones the user's voice from all recorded memory audio and stores the
    /// resulting voice id on the persona so replies are spoken in their voice.
    func cloneVoiceFromMemories() async {
        guard !isCloningVoice else { return }

        let recordedAudioURLs = memoryStore.capturedMemories.compactMap { memory in
            memoryStore.audioFileURL(for: memory)
        }
        guard !recordedAudioURLs.isEmpty else {
            lastErrorMessage = "Record a few memories out loud before cloning your voice."
            return
        }

        isCloningVoice = true
        lastErrorMessage = nil

        var personaBeingCloned = memoryStore.persona
        personaBeingCloned.voiceCloneStatus = .inProgress
        memoryStore.updatePersona(personaBeingCloned)

        let voiceName = memoryStore.persona.ownerDisplayName.isEmpty
            ? "Clicky Legacy Voice"
            : memoryStore.persona.ownerDisplayName

        do {
            let clonedVoiceID = try await voiceCloneService.cloneVoice(
                named: voiceName,
                fromAudioFileURLs: recordedAudioURLs
            )

            var updatedPersona = memoryStore.persona
            updatedPersona.clonedVoiceID = clonedVoiceID
            updatedPersona.voiceCloneStatus = .ready
            memoryStore.updatePersona(updatedPersona)
        } catch {
            var failedPersona = memoryStore.persona
            failedPersona.voiceCloneStatus = .failed(message: error.localizedDescription)
            memoryStore.updatePersona(failedPersona)
            lastErrorMessage = error.localizedDescription
        }

        isCloningVoice = false
    }

    // MARK: - Persona sync

    /// Uploads the current persona to the backend so it can be restored later.
    func syncPersonaToBackend() async {
        personaSyncState = .syncing
        do {
            try await personaSyncService.uploadPersona(memoryStore.persona)
            personaSyncState = .synced
        } catch {
            personaSyncState = .failed(message: error.localizedDescription)
            lastErrorMessage = "Couldn't sync persona: \(error.localizedDescription)"
        }
    }

    /// Restores a persona from the backend by id, replacing the local persona.
    func restorePersonaFromBackend(personaID: UUID) async {
        do {
            let restoredPersona = try await personaSyncService.downloadPersona(withID: personaID)
            memoryStore.updatePersona(restoredPersona)
        } catch {
            lastErrorMessage = "Couldn't restore persona: \(error.localizedDescription)"
        }
    }
}
