//
//  LegacyMemoryLibraryView.swift
//  leanring-buddy
//
//  Browse, edit, and delete every captured memory. Correcting a transcript here
//  directly improves the consciousness, since the persona is grounded in these
//  exact words. Deleting a memory also removes its audio recording from disk.
//

import SwiftUI

struct LegacyMemoryLibraryView: View {
    @ObservedObject var legacyManager: LegacyManager
    @ObservedObject var memoryStore: LegacyMemoryStore

    /// The memory whose transcript is currently being edited, if any.
    @State private var memoryBeingEdited: LegacyMemory?
    @State private var editedTranscriptText: String = ""

    /// The memory the user has asked to delete, held for the confirmation alert.
    @State private var memoryPendingDeletion: LegacyMemory?

    init(legacyManager: LegacyManager) {
        self.legacyManager = legacyManager
        self.memoryStore = legacyManager.memoryStore
    }

    var body: some View {
        Group {
            if memoryStore.capturedMemories.isEmpty {
                emptyLibraryState
            } else {
                memoryListScrollView
            }
        }
        .alert(
            "Delete this memory?",
            isPresented: deletionAlertBinding,
            presenting: memoryPendingDeletion
        ) { memory in
            Button("Delete", role: .destructive) {
                memoryStore.deleteMemory(memory)
                memoryPendingDeletion = nil
            }
            Button("Keep", role: .cancel) {
                memoryPendingDeletion = nil
            }
        } message: { memory in
            Text("This permanently removes the answer to \"\(memory.promptQuestion)\" and its recording. This can't be undone.")
        }
    }

    // MARK: - List

    private var memoryListScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                libraryHeader

                ForEach(memoryStore.capturedMemories) { memory in
                    memoryCard(memory)
                }
            }
            .padding(20)
        }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Memory Library")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text("\(memoryStore.capturedMemories.count) memories preserved. Edit a transcript to correct what the consciousness remembers.")
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func memoryCard(_ memory: LegacyMemory) -> some View {
        let isEditingThisMemory = memoryBeingEdited?.id == memory.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.category.displayTitle.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.blue400)
                    Text(memory.promptQuestion)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if !isEditingThisMemory {
                    memoryRowActions(memory)
                }
            }

            if isEditingThisMemory {
                transcriptEditor(memory)
            } else {
                Text(memory.transcript.isEmpty ? "(no words were transcribed)" : memory.transcript)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .fill(DS.Colors.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private func memoryRowActions(_ memory: LegacyMemory) -> some View {
        HStack(spacing: 14) {
            Button(action: { beginEditing(memory) }) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Edit transcript")

            Button(action: { memoryPendingDeletion = memory }) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Delete memory")
        }
    }

    private func transcriptEditor(_ memory: LegacyMemory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $editedTranscriptText)
                .font(.system(size: 13))
                .foregroundColor(DS.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .fill(DS.Colors.surface1)
                )

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)

                Button("Save") {
                    saveEditedTranscript(into: memory)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                        .fill(DS.Colors.blue500)
                )
            }
        }
    }

    // MARK: - Empty state

    private var emptyLibraryState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28))
                .foregroundColor(DS.Colors.textTertiary)
            Text("No memories yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text("Switch to Capture and record a few answers. They'll show up here to review and edit.")
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editing

    private func beginEditing(_ memory: LegacyMemory) {
        memoryBeingEdited = memory
        editedTranscriptText = memory.transcript
    }

    private func cancelEditing() {
        memoryBeingEdited = nil
        editedTranscriptText = ""
    }

    private func saveEditedTranscript(into memory: LegacyMemory) {
        var updatedMemory = memory
        updatedMemory.transcript = editedTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        memoryStore.updateMemory(updatedMemory)
        cancelEditing()
    }

    /// Drives the delete confirmation alert from the optional pending memory.
    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { memoryPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { memoryPendingDeletion = nil }
            }
        )
    }
}
