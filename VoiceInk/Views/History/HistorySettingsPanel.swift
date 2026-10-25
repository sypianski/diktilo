import SwiftData
import SwiftUI

struct HistorySettingsPanel: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager

    let onClose: () -> Void

    @AppStorage(CleanupSettingsKeys.isTranscriptionCleanupEnabled) private var isTranscriptionCleanupEnabled = false
    @AppStorage(CleanupSettingsKeys.transcriptionRetentionMinutes) private var transcriptionRetentionMinutes = 24 * 60
    @AppStorage(CleanupSettingsKeys.isAudioCleanupEnabled) private var isAudioCleanupEnabled = false
    @AppStorage(CleanupSettingsKeys.audioRetentionPeriod) private var audioRetentionPeriod = 7

    @State private var isPerformingAudioCleanup = false
    @State private var isShowingAudioConfirmation = false
    @State private var cleanupInfo: (fileCount: Int, totalSize: Int64, transcriptions: [Transcription]) = (0, 0, [])
    @State private var showAudioCleanupResult = false
    @State private var audioCleanupResult: (deletedCount: Int, errorCount: Int) = (0, 0)
    @State private var showTranscriptCleanupResult = false
    @State private var usageText: String?

    var body: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "History Settings", onClose: onClose)

            Form {
                if let usageText {
                    Section {
                        Text(usageText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Usage")
                    }
                }

                Section {
                    Toggle("Auto-delete Transcript History", isOn: $isTranscriptionCleanupEnabled)

                    if isTranscriptionCleanupEnabled {
                        Picker("Delete After", selection: $transcriptionRetentionMinutes) {
                            Text("Immediately").tag(0)
                            Text("1 hour").tag(60)
                            Text("1 day").tag(24 * 60)
                            Text("3 days").tag(3 * 24 * 60)
                            Text("7 days").tag(7 * 24 * 60)
                        }

                        Button("Run Cleanup Now") {
                            Task {
                                await TranscriptionAutoCleanupService.shared.runManualCleanup(modelContext: modelContext)
                                await MainActor.run {
                                    showTranscriptCleanupResult = true
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader(
                        "Transcript History",
                        tip: "Delete transcript history and related audio files after the retention period."
                    )
                }

                Section {
                    Toggle("Auto-delete Audio Files", isOn: $isAudioCleanupEnabled)
                            .disabled(isTranscriptionCleanupEnabled)

                        if isTranscriptionCleanupEnabled {
                            Text("Audio is deleted together with the transcripts.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else if isAudioCleanupEnabled {
                            Picker("Keep Audio For", selection: $audioRetentionPeriod) {
                                Text("1 day").tag(1)
                                Text("3 days").tag(3)
                                Text("7 days").tag(7)
                                Text("14 days").tag(14)
                                Text("30 days").tag(30)
                            }

                            Button {
                                analyzeAudioCleanup()
                            } label: {
                                Text(isPerformingAudioCleanup ? "Analyzing..." : "Run Cleanup Now")
                            }
                            .disabled(isPerformingAudioCleanup)
                        }
                    } header: {
                        sectionHeader(
                            "Audio Files",
                            tip: "Delete old recordings while keeping transcript history."
                        )
                    }

                Section {
                    ForEach(ShortcutAction.historyActions, id: \.storageName) { action in
                        LabeledContent(action.displayName) {
                            ShortcutRecorder(action: action) {
                                recordingShortcutManager.updateShortcutStatus()
                            }
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Shortcuts")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await loadUsage() }
        .alert("Transcript Cleanup", isPresented: $showTranscriptCleanupResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Cleanup complete.")
        }
        .alert("Audio Cleanup", isPresented: $isShowingAudioConfirmation) {
            Button("Cancel", role: .cancel) { }

            if cleanupInfo.fileCount > 0 {
                Button(String(localized: "Delete \(cleanupInfo.fileCount) Files"), role: .destructive) {
                    runAudioCleanup()
                }
            }
        } message: {
            if cleanupInfo.fileCount > 0 {
                Text(String(localized: "This will delete \(cleanupInfo.fileCount) audio files (\(AudioCleanupManager.shared.formatFileSize(cleanupInfo.totalSize)))."))
            } else {
                Text(String(localized: "No audio files found older than \(audioRetentionPeriod) days."))
            }
        }
        .alert("Cleanup Complete", isPresented: $showAudioCleanupResult) {
            Button("OK", role: .cancel) { }
        } message: {
            if audioCleanupResult.errorCount > 0 {
                Text(String(format: String(localized: "Deleted files: %lld. Failed: %lld."), Int64(audioCleanupResult.deletedCount), Int64(audioCleanupResult.errorCount)))
            } else {
                Text(String(localized: "Deleted \(audioCleanupResult.deletedCount) audio files."))
            }
        }
        .onChange(of: isTranscriptionCleanupEnabled) { _, newValue in
            if newValue {
                isAudioCleanupEnabled = false
                AudioCleanupManager.shared.stopAutomaticCleanup()
            } else if isAudioCleanupEnabled {
                AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
            }
        }
        .onChange(of: isAudioCleanupEnabled) { _, newValue in
            guard !isTranscriptionCleanupEnabled else {
                if newValue {
                    isAudioCleanupEnabled = false
                }
                AudioCleanupManager.shared.stopAutomaticCleanup()
                return
            }

            if newValue {
                AudioCleanupManager.shared.startAutomaticCleanup(modelContext: modelContext)
            } else {
                AudioCleanupManager.shared.stopAutomaticCleanup()
            }
        }
    }

    /// "1 284 entries · 412 MB of recordings", counted from the store and the audio files on disk.
    private func loadUsage() async {
        let count = (try? modelContext.fetchCount(FetchDescriptor<Transcription>())) ?? 0
        var withAudio = FetchDescriptor<Transcription>(
            predicate: #Predicate<Transcription> { $0.audioFileURL != nil }
        )
        withAudio.propertiesToFetch = [\.audioFileURL]
        let items = (try? modelContext.fetch(withAudio)) ?? []
        var bytes: Int64 = 0
        for item in items {
            guard let urlString = item.audioFileURL, let url = URL(string: urlString),
                  let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else { continue }
            bytes += size
        }

        usageText = String(
            format: String(localized: "%lld entries · %@ of recordings"),
            Int64(count),
            AudioCleanupManager.shared.formatFileSize(bytes)
        )
    }

    private func sectionHeader(_ title: LocalizedStringKey, tip: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(title)

            InfoTip(message: tip, iconSize: .small, iconColor: .secondary, width: 260)
        }
    }

    private func analyzeAudioCleanup() {
        Task {
            await MainActor.run { isPerformingAudioCleanup = true }
            let info = await AudioCleanupManager.shared.getCleanupInfo(modelContext: modelContext)
            await MainActor.run {
                cleanupInfo = info
                isPerformingAudioCleanup = false
                isShowingAudioConfirmation = true
            }
        }
    }

    private func runAudioCleanup() {
        Task {
            await MainActor.run { isPerformingAudioCleanup = true }
            let result = await AudioCleanupManager.shared.runCleanupForTranscriptions(
                modelContext: modelContext,
                transcriptions: cleanupInfo.transcriptions
            )
            await MainActor.run {
                audioCleanupResult = result
                isPerformingAudioCleanup = false
                showAudioCleanupResult = true
            }
        }
    }
}
