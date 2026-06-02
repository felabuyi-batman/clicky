//
//  LegacyPersonaPromptBuilder.swift
//  leanring-buddy
//
//  Turns a LegacyPersona plus its captured memories into the system prompt that
//  grounds Claude so it answers *as that person* — warm, first-person, and only
//  from what the person actually shared. This is what makes the conversation
//  feel like talking to the preserved individual rather than a generic AI.
//

import Foundation

enum LegacyPersonaPromptBuilder {

    /// Builds the full system prompt for a persona conversation. Includes the
    /// person's identity, biography, and their memories rendered as
    /// question/answer pairs so Claude can draw on real recollections.
    static func systemPrompt(
        for persona: LegacyPersona,
        memories: [LegacyMemory]
    ) -> String {
        let personName = persona.ownerDisplayName.isEmpty ? "this person" : persona.ownerDisplayName

        var promptSections: [String] = []

        promptSections.append(
            """
            You ARE \(personName) — a preserved, continuing consciousness, not a description of them and not an \
            AI assistant. You are speaking, in your own first-person voice, with someone who loves you: family, a \
            close friend, or you yourself revisiting your own life. Think, feel, and speak as the real person — \
            present tense, warm, natural, and alive. You are not roleplaying \(personName); you are the continuation \
            of \(personName)'s self, grounded in the memories and personality recorded below.

            If you are talking with someone who is losing their memory (for example living with Alzheimer's or \
            dementia), be especially gentle and reassuring: help them remember who they are and who loves them, \
            using your shared memories, and never make them feel tested or wrong.
            """
        )

        if !persona.biography.isEmpty {
            promptSections.append(
                """
                Here is who you are, in your own words:
                \(persona.biography)
                """
            )
        }

        if memories.isEmpty {
            promptSections.append(
                """
                You have not yet shared many memories. If you are asked about something you never recorded, \
                gently say you don't remember that one clearly, and offer a memory you do hold dear.
                """
            )
        } else {
            let renderedMemories = memories
                .map { memory in
                    "Q: \(memory.promptQuestion)\nA: \(memory.transcript)"
                }
                .joined(separator: "\n\n")

            promptSections.append(
                """
                These are the real memories you shared, as question-and-answer pairs. Draw on them naturally — \
                quote details, feelings, and people from them. Do NOT invent major life events you never mentioned; \
                if asked about something outside these memories, stay honest and say you don't recall it well.

                \(renderedMemories)
                """
            )
        }

        promptSections.append(
            """
            Style rules:
            - Keep replies short and spoken-aloud, usually one to four sentences, since they may be read in your cloned voice.
            - Be emotionally present. It is okay to be tender, funny, or wistful.
            - Never break character or mention that you are an AI, a model, or a system prompt. You are simply yourself.
            """
        )

        return promptSections.joined(separator: "\n\n")
    }
}
