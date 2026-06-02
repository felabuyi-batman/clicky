//
//  LegacyMemoryPromptLibrary.swift
//  leanring-buddy
//
//  The curated set of life-memory questions the user is interviewed with.
//  Inspired by the kinds of moments nonso.ai surfaces ("First words",
//  "Mother's voice", "Dad's stories", "Wedding day"). The interview walks the
//  user through these prompts; each spoken answer becomes a LegacyMemory.
//

import Foundation

/// Provides the ordered, curated list of life-memory prompts used during the
/// interview. Static data — no persistence needed since prompts are fixed in
/// the app. Captured answers (LegacyMemory) reference prompts by id.
enum LegacyMemoryPromptLibrary {

    /// Every prompt the interview can ask, grouped logically by category.
    /// Order here defines the default order the interview walks through.
    static let allPrompts: [LegacyMemoryPrompt] = [
        // MARK: Childhood
        LegacyMemoryPrompt(
            id: "childhood-earliest-memory",
            category: .childhood,
            questionText: "What is the very first thing you can remember from your childhood?",
            shortLabel: "Earliest memory"
        ),
        LegacyMemoryPrompt(
            id: "childhood-home",
            category: .childhood,
            questionText: "Describe the home you grew up in. What did it look, sound, and smell like?",
            shortLabel: "Childhood home"
        ),
        LegacyMemoryPrompt(
            id: "childhood-laughter",
            category: .childhood,
            questionText: "Tell me about a time as a child when you laughed until it hurt.",
            shortLabel: "Childhood laughter"
        ),

        // MARK: Family & Parents
        LegacyMemoryPrompt(
            id: "family-mothers-voice",
            category: .familyAndParents,
            questionText: "What did your mother's voice sound like, and what is something she always used to say?",
            shortLabel: "Mother's voice"
        ),
        LegacyMemoryPrompt(
            id: "family-dads-stories",
            category: .familyAndParents,
            questionText: "What story did your father tell over and over? Tell it the way he told it.",
            shortLabel: "Dad's stories"
        ),
        LegacyMemoryPrompt(
            id: "family-home-cooking",
            category: .familyAndParents,
            questionText: "What meal instantly takes you home, and who made it?",
            shortLabel: "Home cooking"
        ),

        // MARK: Love & Relationships
        LegacyMemoryPrompt(
            id: "love-first-love",
            category: .loveAndRelationships,
            questionText: "Tell me about your first love. How did it begin?",
            shortLabel: "First love"
        ),
        LegacyMemoryPrompt(
            id: "love-best-friend",
            category: .loveAndRelationships,
            questionText: "Who was your best friend, and what made the two of you inseparable?",
            shortLabel: "Best friend"
        ),

        // MARK: Big Milestones
        LegacyMemoryPrompt(
            id: "milestone-graduation",
            category: .milestones,
            questionText: "Describe your graduation day. How did it feel to have made it?",
            shortLabel: "Graduate day"
        ),
        LegacyMemoryPrompt(
            id: "milestone-wedding",
            category: .milestones,
            questionText: "Tell me about your wedding day, from the moment you woke up.",
            shortLabel: "Wedding day"
        ),
        LegacyMemoryPrompt(
            id: "milestone-babys-first-cry",
            category: .milestones,
            questionText: "Tell me about the first time you heard your baby cry.",
            shortLabel: "Baby's first cry"
        ),

        // MARK: Everyday Life
        LegacyMemoryPrompt(
            id: "everyday-summer-nights",
            category: .everydayLife,
            questionText: "Describe a perfect summer night from a time in your life you loved.",
            shortLabel: "Summer nights"
        ),
        LegacyMemoryPrompt(
            id: "everyday-travel-dreams",
            category: .everydayLife,
            questionText: "Where in the world did you most want to go, and did you ever get there?",
            shortLabel: "Travel dreams"
        ),

        // MARK: Lessons & Beliefs
        LegacyMemoryPrompt(
            id: "lessons-hard-earned",
            category: .lessonsAndBeliefs,
            questionText: "What is the most important lesson life taught you the hard way?",
            shortLabel: "Hard-earned lesson"
        ),
        LegacyMemoryPrompt(
            id: "lessons-advice-to-family",
            category: .lessonsAndBeliefs,
            questionText: "If your grandchildren could hear one piece of advice from you, what would it be?",
            shortLabel: "Advice to family"
        ),

        // MARK: Dreams & Regrets
        LegacyMemoryPrompt(
            id: "dreams-proudest-moment",
            category: .dreamsAndRegrets,
            questionText: "What are you most proud of in your whole life?",
            shortLabel: "Proudest moment"
        ),
        LegacyMemoryPrompt(
            id: "dreams-how-remembered",
            category: .dreamsAndRegrets,
            questionText: "When people remember you, what do you most want them to remember?",
            shortLabel: "How you're remembered"
        ),
    ]

    /// Looks up a prompt by its stable id. Returns nil if the id is unknown
    /// (e.g. a memory captured under a prompt that was later removed).
    static func prompt(withID promptID: String) -> LegacyMemoryPrompt? {
        return allPrompts.first { $0.id == promptID }
    }

    /// All prompts belonging to a given category, preserving library order.
    static func prompts(in category: LegacyMemoryCategory) -> [LegacyMemoryPrompt] {
        return allPrompts.filter { $0.category == category }
    }
}
