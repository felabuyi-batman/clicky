//
//  LegacyInterviewView.swift
//  leanring-buddy
//
//  The interview screen of the legacy feature. Walks the user through curated
//  life-memory prompts; for each one they record a spoken answer, which is
//  transcribed and saved as a memory (and kept as voice-cloning material).
//

import SwiftUI

struct LegacyInterviewView: View {
    @ObservedObject var legacyManager: LegacyManager
    @StateObject private var memoryRecorder = LegacyMemoryRecorder()

    /// The prompt currently being answered. Starts at the first unanswered
    /// prompt, then advances as the user records answers.
    @State private var currentPrompt: LegacyMemoryPrompt
    @State private var inlineErrorMessage: String?
    @State private var isSavingMemory = false

    init(legacyManager: LegacyManager) {
        self.legacyManager = legacyManager
        // Resume at the first prompt the user hasn't answered yet, or the very
        // first prompt if they're just starting.
        let startingPrompt = legacyManager.memoryStore.nextUnansweredPrompt
            ?? LegacyMemoryPromptLibrary.allPrompts[0]
        _currentPrompt = State(initialValue: startingPrompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            progressHeader
            promptCard
            recordingControls

            if let existingMemory = legacyManager.memoryStore.mostRecentMemory(forPromptID: currentPrompt.id) {
                answeredMemoryCard(existingMemory)
            }

            if let inlineErrorMessage {
                Text(inlineErrorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            promptNavigation
        }
        .padding(20)
    }

    // MARK: - Progress

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preserve a memory")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)

            Text("\(legacyManager.memoryStore.answeredPromptCount) of \(legacyManager.memoryStore.totalPromptCount) memories captured")
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: - Prompt card

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentPrompt.category.displayTitle.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.Colors.blue400)

            Text(currentPrompt.questionText)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(DS.Colors.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Recording controls

    private var recordingControls: some View {
        HStack(spacing: 12) {
            Button(action: { toggleRecording() }) {
                HStack(spacing: 8) {
                    Image(systemName: memoryRecorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(recordButtonTitle)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .fill(memoryRecorder.isRecording ? Color.red.opacity(0.85) : DS.Colors.blue500)
                )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(isSavingMemory)

            if memoryRecorder.isRecording {
                audioMeter
                Text(formattedElapsedTime)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(DS.Colors.textSecondary)
            } else if isSavingMemory {
                Text("Transcribing…")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textTertiary)
            }
        }
    }

    private var audioMeter: some View {
        // A simple level bar that reacts to the live microphone power.
        RoundedRectangle(cornerRadius: DS.CornerRadius.pill, style: .continuous)
            .fill(DS.Colors.blue400)
            .frame(width: max(8, 80 * memoryRecorder.currentAudioPowerLevel), height: 6)
            .animation(.linear(duration: 0.05), value: memoryRecorder.currentAudioPowerLevel)
    }

    private var recordButtonTitle: String {
        if memoryRecorder.isRecording { return "Stop & Save" }
        return legacyManager.memoryStore.mostRecentMemory(forPromptID: currentPrompt.id) != nil
            ? "Re-record"
            : "Record Answer"
    }

    private var formattedElapsedTime: String {
        let totalSeconds = Int(memoryRecorder.elapsedRecordingSeconds)
        return String(format: "%01d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    // MARK: - Answered memory

    private func answeredMemoryCard(_ memory: LegacyMemory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR ANSWER")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.Colors.success)
            Text(memory.transcript.isEmpty ? "(no words were transcribed)" : memory.transcript)
                .font(.system(size: 13))
                .foregroundColor(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                .fill(DS.Colors.surface1)
        )
    }

    // MARK: - Navigation

    private var promptNavigation: some View {
        HStack {
            Button(action: { moveToAdjacentPrompt(offset: -1) }) {
                Label("Previous", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(currentPromptIndex == 0)

            Spacer()

            Button(action: { moveToAdjacentPrompt(offset: 1) }) {
                Label("Next", systemImage: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(currentPromptIndex >= LegacyMemoryPromptLibrary.allPrompts.count - 1)
        }
    }

    private var currentPromptIndex: Int {
        LegacyMemoryPromptLibrary.allPrompts.firstIndex(where: { $0.id == currentPrompt.id }) ?? 0
    }

    private func moveToAdjacentPrompt(offset: Int) {
        let allPrompts = LegacyMemoryPromptLibrary.allPrompts
        let newIndex = currentPromptIndex + offset
        guard allPrompts.indices.contains(newIndex) else { return }
        if memoryRecorder.isRecording {
            memoryRecorder.cancelRecording()
        }
        inlineErrorMessage = nil
        currentPrompt = allPrompts[newIndex]
    }

    // MARK: - Actions

    private func toggleRecording() {
        if memoryRecorder.isRecording {
            finishRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        inlineErrorMessage = nil
        Task {
            do {
                try await memoryRecorder.startRecording(
                    intoDirectory: legacyManager.memoryStore.recordingsDirectory
                )
            } catch {
                inlineErrorMessage = error.localizedDescription
            }
        }
    }

    private func finishRecording() {
        isSavingMemory = true
        Task {
            do {
                let recordingResult = try await memoryRecorder.stopRecordingAndTranscribe()
                legacyManager.saveRecordedMemory(forPrompt: currentPrompt, recordingResult: recordingResult)
                // Advance to the next unanswered prompt to keep the interview moving.
                if let nextPrompt = legacyManager.memoryStore.nextUnansweredPrompt {
                    currentPrompt = nextPrompt
                }
            } catch {
                inlineErrorMessage = error.localizedDescription
            }
            isSavingMemory = false
        }
    }
}
