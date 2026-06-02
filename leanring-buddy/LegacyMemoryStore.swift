//
//  LegacyMemoryStore.swift
//  leanring-buddy
//
//  Persists the legacy memory library and the assembled persona to disk and
//  exposes them as observable state for the interview and conversation UI.
//
//  Layout on disk (inside the app's Application Support directory):
//    Clicky/Legacy/memories.json   → [LegacyMemory] encoded as JSON
//    Clicky/Legacy/persona.json    → LegacyPersona encoded as JSON
//    Clicky/Legacy/Recordings/     → one audio file per recorded memory
//
//  Audio files are referenced from LegacyMemory.audioFileName (file name only)
//  so the library JSON stays portable and the absolute path can be rebuilt from
//  the recordings directory.
//

import Foundation

@MainActor
final class LegacyMemoryStore: ObservableObject {

    /// All captured memories, ordered by capture time (oldest first).
    @Published private(set) var capturedMemories: [LegacyMemory] = []

    /// The assembled persona. Always present (created with empty fields on first
    /// launch) so the UI can bind to it without optional juggling.
    @Published private(set) var persona: LegacyPersona

    // MARK: - Disk locations

    private let legacyDirectoryURL: URL
    private let recordingsDirectoryURL: URL
    private let memoriesFileURL: URL
    private let personaFileURL: URL

    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init() {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyDirectory = applicationSupportURL
            .appendingPathComponent("Clicky", isDirectory: true)
            .appendingPathComponent("Legacy", isDirectory: true)
        let recordingsDirectory = legacyDirectory.appendingPathComponent("Recordings", isDirectory: true)

        self.legacyDirectoryURL = legacyDirectory
        self.recordingsDirectoryURL = recordingsDirectory
        self.memoriesFileURL = legacyDirectory.appendingPathComponent("memories.json")
        self.personaFileURL = legacyDirectory.appendingPathComponent("persona.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder

        // Start with an empty persona; replaced below if one exists on disk.
        self.persona = LegacyPersona()

        createDirectoriesIfNeeded()
        loadFromDisk()
    }

    // MARK: - Public derived state

    /// The absolute on-disk URL of a memory's audio recording, if it has one.
    func audioFileURL(for memory: LegacyMemory) -> URL? {
        guard let audioFileName = memory.audioFileName else { return nil }
        return recordingsDirectoryURL.appendingPathComponent(audioFileName)
    }

    /// The directory new recordings should be written into. Exposed so the
    /// recording pipeline can write audio straight to its final location.
    var recordingsDirectory: URL {
        recordingsDirectoryURL
    }

    /// The most recent memory captured for a given prompt, if any. Used by the
    /// interview UI to show whether a prompt has already been answered.
    func mostRecentMemory(forPromptID promptID: String) -> LegacyMemory? {
        return capturedMemories
            .filter { $0.promptID == promptID }
            .max { $0.createdAt < $1.createdAt }
    }

    /// The next prompt in library order that has not yet been answered, or nil
    /// when every prompt has at least one captured memory.
    var nextUnansweredPrompt: LegacyMemoryPrompt? {
        let answeredPromptIDs = Set(capturedMemories.map { $0.promptID })
        return LegacyMemoryPromptLibrary.allPrompts.first { !answeredPromptIDs.contains($0.id) }
    }

    /// How many distinct prompts have been answered, for progress display.
    var answeredPromptCount: Int {
        Set(capturedMemories.map { $0.promptID }).count
    }

    var totalPromptCount: Int {
        LegacyMemoryPromptLibrary.allPrompts.count
    }

    /// Total seconds of recorded audio gathered so far. ElevenLabs instant voice
    /// cloning wants a reasonable amount of clean speech, so the UI uses this to
    /// tell the user when there's enough material to clone their voice.
    var totalRecordedAudioSeconds: Double {
        capturedMemories.reduce(0) { runningTotal, memory in
            runningTotal + memory.recordedDurationSeconds
        }
    }

    // MARK: - Mutations

    /// Adds a newly captured memory and persists the library to disk.
    func addMemory(_ memory: LegacyMemory) {
        capturedMemories.append(memory)
        persistMemories()
    }

    /// Replaces an existing memory (matched by id) and persists. Used when the
    /// user edits a transcript or re-records an answer.
    func updateMemory(_ updatedMemory: LegacyMemory) {
        guard let existingIndex = capturedMemories.firstIndex(where: { $0.id == updatedMemory.id }) else {
            return
        }
        var memoryToStore = updatedMemory
        memoryToStore.updatedAt = Date()
        capturedMemories[existingIndex] = memoryToStore
        persistMemories()
    }

    /// Removes a memory and deletes its audio recording from disk.
    func deleteMemory(_ memory: LegacyMemory) {
        capturedMemories.removeAll { $0.id == memory.id }
        if let audioURL = audioFileURL(for: memory) {
            try? FileManager.default.removeItem(at: audioURL)
        }
        persistMemories()
    }

    /// Updates the persona (identity, biography, cloned voice) and persists.
    func updatePersona(_ updatedPersona: LegacyPersona) {
        var personaToStore = updatedPersona
        personaToStore.updatedAt = Date()
        persona = personaToStore
        persistPersona()
    }

    // MARK: - Persistence

    private func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true)
    }

    private func loadFromDisk() {
        if let memoriesData = try? Data(contentsOf: memoriesFileURL),
           let decodedMemories = try? jsonDecoder.decode([LegacyMemory].self, from: memoriesData) {
            capturedMemories = decodedMemories.sorted { $0.createdAt < $1.createdAt }
        }

        if let personaData = try? Data(contentsOf: personaFileURL),
           let decodedPersona = try? jsonDecoder.decode(LegacyPersona.self, from: personaData) {
            persona = decodedPersona
        }
    }

    private func persistMemories() {
        guard let encodedData = try? jsonEncoder.encode(capturedMemories) else {
            print("⚠️ LegacyMemoryStore: failed to encode memories")
            return
        }
        do {
            try encodedData.write(to: memoriesFileURL, options: .atomic)
        } catch {
            print("⚠️ LegacyMemoryStore: failed to write memories: \(error)")
        }
    }

    private func persistPersona() {
        guard let encodedData = try? jsonEncoder.encode(persona) else {
            print("⚠️ LegacyMemoryStore: failed to encode persona")
            return
        }
        do {
            try encodedData.write(to: personaFileURL, options: .atomic)
        } catch {
            print("⚠️ LegacyMemoryStore: failed to write persona: \(error)")
        }
    }
}
