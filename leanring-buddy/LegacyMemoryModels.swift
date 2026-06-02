//
//  LegacyMemoryModels.swift
//  leanring-buddy
//
//  Domain models for the "digital immortality" legacy feature. The user is
//  interviewed with life-memory prompts (e.g. "Tell me about your first love").
//  Each spoken answer becomes a LegacyMemory (transcript + recorded audio).
//  Together the collected memories plus a cloned voice form a LegacyPersona —
//  an AI the user and their family can talk to later.
//
//  These types are Codable so they can be persisted locally as JSON and synced
//  to the backend Worker.
//

import Foundation

/// A broad theme used to group the life-memory prompts shown during the
/// interview. Mirrors the kinds of moments nonso.ai surfaces (childhood,
/// love, family, milestones, everyday life).
enum LegacyMemoryCategory: String, Codable, CaseIterable, Identifiable {
    case childhood
    case familyAndParents
    case loveAndRelationships
    case milestones
    case everydayLife
    case lessonsAndBeliefs
    case dreamsAndRegrets

    var id: String { rawValue }

    /// Human-readable title shown as a section header in the interview UI.
    var displayTitle: String {
        switch self {
        case .childhood:
            return "Childhood"
        case .familyAndParents:
            return "Family & Parents"
        case .loveAndRelationships:
            return "Love & Relationships"
        case .milestones:
            return "Big Milestones"
        case .everydayLife:
            return "Everyday Life"
        case .lessonsAndBeliefs:
            return "Lessons & Beliefs"
        case .dreamsAndRegrets:
            return "Dreams & Regrets"
        }
    }
}

/// A single life-memory question the user is asked to answer out loud.
/// The prompt library is curated (see LegacyMemoryPromptLibrary) but the
/// model is Codable so custom prompts can be added and synced later.
struct LegacyMemoryPrompt: Codable, Identifiable, Hashable {
    let id: String
    let category: LegacyMemoryCategory
    /// The full question read to the user, e.g. "What is your earliest memory?"
    let questionText: String
    /// A short label used on compact UI like the floating prompt chips,
    /// e.g. "Earliest memory".
    let shortLabel: String
}

/// One captured answer to a memory prompt. Holds both the transcribed text and
/// a reference to the locally stored audio recording (used both for playback
/// and as training material for voice cloning).
struct LegacyMemory: Codable, Identifiable, Hashable {
    let id: UUID
    /// The prompt this memory answers. Stored by id so prompts can evolve.
    let promptID: String
    /// The exact question that was asked, denormalized so a memory remains
    /// readable even if the prompt library changes.
    let promptQuestion: String
    let category: LegacyMemoryCategory
    /// The transcribed answer the user spoke.
    var transcript: String
    /// File name (not full path) of the recorded audio within the audio
    /// directory. Nil when only text was captured (e.g. typed answer).
    var audioFileName: String?
    /// Length of the recorded answer in seconds, used to track how much voice
    /// material has been gathered for cloning.
    var recordedDurationSeconds: Double
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        promptID: String,
        promptQuestion: String,
        category: LegacyMemoryCategory,
        transcript: String,
        audioFileName: String? = nil,
        recordedDurationSeconds: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.promptID = promptID
        self.promptQuestion = promptQuestion
        self.category = category
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.recordedDurationSeconds = recordedDurationSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Progress states for cloning the user's voice from their recorded memories.
enum LegacyVoiceCloneStatus: Codable, Equatable {
    /// No voice has been cloned yet and none is in progress.
    case notStarted
    /// A clone request is currently being processed by the backend.
    case inProgress
    /// Cloning succeeded; the associated ElevenLabs voice id is stored on the persona.
    case ready
    /// Cloning failed; the associated message explains why.
    case failed(message: String)
}

/// The assembled "digital you": identity, the cloned-voice id used for TTS
/// replies, and a generated biography that grounds the AI's personality. The
/// memories themselves live in the store keyed separately so the persona stays
/// lightweight to sync.
struct LegacyPersona: Codable, Identifiable, Hashable {
    let id: UUID
    /// The name of the person being preserved, e.g. "Grandma Rose".
    var ownerDisplayName: String
    /// The ElevenLabs voice id produced by cloning the user's recordings.
    /// Nil until voice cloning completes successfully.
    var clonedVoiceID: String?
    var voiceCloneStatus: LegacyVoiceCloneStatus
    /// A first-person biography distilled from the captured memories. Used as
    /// the system prompt grounding so the AI speaks as this person.
    var biography: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerDisplayName: String = "",
        clonedVoiceID: String? = nil,
        voiceCloneStatus: LegacyVoiceCloneStatus = .notStarted,
        biography: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerDisplayName = ownerDisplayName
        self.clonedVoiceID = clonedVoiceID
        self.voiceCloneStatus = voiceCloneStatus
        self.biography = biography
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// True once a cloned voice exists and can be used for spoken replies.
    var hasClonedVoice: Bool {
        if case .ready = voiceCloneStatus, clonedVoiceID != nil {
            return true
        }
        return false
    }
}
