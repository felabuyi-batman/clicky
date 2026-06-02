//
//  LegacyHomeView.swift
//  leanring-buddy
//
//  Top-level container for the "digital immortality" feature. Lets the user name
//  the person being preserved, switch between the interview (capture memories)
//  and conversation (talk to the memory) modes, and run the two assembly steps:
//  building the biography and cloning the voice.
//

import SwiftUI

struct LegacyHomeView: View {
    @ObservedObject var legacyManager: LegacyManager

    private enum LegacyMode: String, CaseIterable, Identifiable {
        case interview = "Capture"
        case library = "Library"
        case conversation = "Talk"
        var id: String { rawValue }
    }

    @State private var selectedMode: LegacyMode = .interview
    @State private var ownerNameInput: String = ""

    init(legacyManager: LegacyManager) {
        self.legacyManager = legacyManager
        _ownerNameInput = State(initialValue: legacyManager.memoryStore.persona.ownerDisplayName)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(DS.Colors.borderSubtle)

            switch selectedMode {
            case .interview:
                LegacyInterviewView(legacyManager: legacyManager)
            case .library:
                LegacyMemoryLibraryView(legacyManager: legacyManager)
            case .conversation:
                LegacyConversationView(legacyManager: legacyManager)
            }

            Divider().background(DS.Colors.borderSubtle)
            assemblyFooter
        }
        .frame(minWidth: 460, minHeight: 560)
        .background(DS.Colors.background)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "infinity")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.blue400)
                Text("Preserve a Voice")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Who are we preserving?")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textTertiary)
                TextField("e.g. Grandma Rose", text: $ownerNameInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                            .fill(DS.Colors.surface1)
                    )
                    .onSubmit { legacyManager.updateOwnerDisplayName(ownerNameInput) }
                    .onChange(of: ownerNameInput) { _, newValue in
                        legacyManager.updateOwnerDisplayName(newValue)
                    }
            }

            Picker("", selection: $selectedMode) {
                ForEach(LegacyMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(20)
    }

    // MARK: - Assembly footer (biography + voice clone)

    private var assemblyFooter: some View {
        HStack(spacing: 12) {
            assemblyButton(
                title: legacyManager.isBuildingBiography ? "Building…" : "Build Biography",
                systemImage: "doc.text",
                isBusy: legacyManager.isBuildingBiography,
                isEnabled: !legacyManager.memoryStore.capturedMemories.isEmpty
            ) {
                Task { await legacyManager.buildBiographyFromMemories() }
            }

            assemblyButton(
                title: legacyManager.isCloningVoice ? "Cloning…" : "Clone Voice",
                systemImage: "waveform",
                isBusy: legacyManager.isCloningVoice,
                isEnabled: legacyManager.hasEnoughAudioToCloneVoice
            ) {
                Task { await legacyManager.cloneVoiceFromMemories() }
            }

            Spacer()

            if let errorMessage = legacyManager.lastErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: 180, alignment: .trailing)
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    voiceCloneStatusLabel
                    personaSyncStatusLabel
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func assemblyButton(
        title: String,
        systemImage: String,
        isBusy: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isEnabled ? DS.Colors.textPrimary : DS.Colors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(DS.Colors.surface2)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(!isEnabled || isBusy)
    }

    private var voiceCloneStatusLabel: some View {
        let recordedSeconds = Int(legacyManager.memoryStore.totalRecordedAudioSeconds)
        let neededSeconds = Int(LegacyManager.minimumRecordedSecondsForCloning)
        let statusText: String

        if legacyManager.memoryStore.persona.hasClonedVoice {
            statusText = "Voice cloned ✓"
        } else if legacyManager.hasEnoughAudioToCloneVoice {
            statusText = "Ready to clone voice"
        } else {
            statusText = "\(recordedSeconds)s / \(neededSeconds)s recorded for voice clone"
        }

        return Text(statusText)
            .font(.system(size: 11))
            .foregroundColor(DS.Colors.textTertiary)
    }

    /// Shows that the consciousness is backed up to the cloud (so it isn't only
    /// on this Mac), reflecting the auto-sync state driven by LegacyManager.
    private var personaSyncStatusLabel: some View {
        let syncText: String
        let syncColor: Color

        switch legacyManager.personaSyncState {
        case .idle:
            syncText = "Not synced yet"
            syncColor = DS.Colors.textTertiary
        case .syncing:
            syncText = "Backing up…"
            syncColor = DS.Colors.textTertiary
        case .synced:
            syncText = "Backed up to cloud ✓"
            syncColor = DS.Colors.success
        case .failed:
            syncText = "Backup failed — will retry on next change"
            syncColor = DS.Colors.textTertiary
        }

        return Text(syncText)
            .font(.system(size: 10))
            .foregroundColor(syncColor)
    }
}
