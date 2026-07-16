import SwiftUI
import Cocoa
import Carbon.HIToolbox
import LaunchAtLogin

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = true
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @AppStorage(AppAppearancePreference.userDefaultsKey) private var appAppearancePreference = AppAppearancePreference.system
    @AppStorage(AppLanguagePreference.userDefaultsKey) private var appLanguagePreference = AppLanguagePreference.systemValue
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage("RecorderDestinationHUDEnabled") private var destinationHUDEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isRealtimeEnabled) private var globalRealtimeEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isTextFormattingEnabled) private var globalTextFormattingEnabled = true
    @State private var showResetOnboardingAlert = false
    @State private var showLanguageRestartAlert = false
    @State private var isShowingSaveTargets = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(.accentColor)
                    Text("Keyboard shortcuts and paste behavior moved to the Modes screen.")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open Modes") {
                        NotificationCenter.default.post(
                            name: .navigateToDestination,
                            object: nil,
                            userInfo: ["destination": ViewType.modes.rawValue]
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Section("Transcription") {
                Toggle(isOn: $globalRealtimeEnabled) {
                    HStack(spacing: 4) {
                        Text("Real-time Streaming")
                        InfoTip("Stream audio to the transcription server while you speak. Falls back to batch transcription automatically when unavailable. Applies to every profile.")
                    }
                }

                Toggle(isOn: $globalTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text("Paragraph Formatting")
                        InfoTip("Break large blocks of transcribed text into paragraphs. Applies to every profile.")
                    }
                }

                LabeledContent("Model & Language") {
                    Text("Set in the AI Models tab")
                        .foregroundColor(.secondary)
                }
            }

            Section("Interface") {
                Picker("Appearance", selection: $appAppearancePreference) {
                    ForEach(AppAppearancePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appAppearancePreference) { _, newValue in
                    newValue.apply()
                }

                Picker("Language", selection: $appLanguagePreference) {
                    ForEach(AppLanguagePreference.availableOptions) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appLanguagePreference) { oldValue, newValue in
                    guard oldValue != newValue else { return }
                    let normalizedValue = AppLanguagePreference.normalizedRawValue(newValue)
                    if normalizedValue != newValue {
                        appLanguagePreference = normalizedValue
                        return
                    }
                    AppLanguagePreference.apply(rawValue: normalizedValue)
                    showLanguageRestartAlert = true
                }

                Picker("Recorder Style", selection: $recorderUIManager.recorderPanelStyle) {
                    ForEach(RecorderPanelStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Toggle(isOn: $showLiveTranscript) {
                    HStack(spacing: 4) {
                        Text("Live Text Display")
                        InfoTip("Shows live text while recording with realtime models.")
                    }
                }

                Toggle(isOn: $destinationHUDEnabled) {
                    HStack(spacing: 4) {
                        Text("Destination Shortcut Hints")
                        InfoTip("Show a compact bar with finish-destination shortcuts (Copy, Paste, Edit Window, Save Targets) while recording.")
                    }
                }
            }

            Section("General") {
                Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)

                LaunchAtLogin.Toggle(String(localized: "Launch at Login"))

                Toggle("Auto-check Updates", isOn: Binding(
                    get: { updaterViewModel.automaticallyChecksForUpdates },
                    set: { updaterViewModel.setAutomaticallyChecksForUpdates($0) }
                ))

                Toggle("Show Announcements", isOn: $enableAnnouncements)
                    .onChange(of: enableAnnouncements) { _, newValue in
                        if newValue {
                            AnnouncementsService.shared.start()
                        } else {
                            AnnouncementsService.shared.stop()
                        }
                    }

                HStack {
                    Button("Check for Updates") {
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)

                    Button("Reset Onboarding") {
                        showResetOnboardingAlert = true
                    }
                }
            }

            Section {
                LabeledContent("Export Settings") {
                    Button("Export") {
                        ImportExportService.shared.exportSettings(
                            enhancementService: enhancementService,
                            recordingShortcutManager: recordingShortcutManager,
                            menuBarManager: menuBarManager,
                            mediaController: mediaController,
                            playbackController: playbackController,
                            recorderUIManager: recorderUIManager,
                            modelContext: modelContext
                        )
                    }
                }

                LabeledContent("Import Settings") {
                    Button("Import") {
                        ImportExportService.shared.importSettings(
                            enhancementService: enhancementService,
                            recordingShortcutManager: recordingShortcutManager,
                            menuBarManager: menuBarManager,
                            mediaController: mediaController,
                            playbackController: playbackController,
                            recorderUIManager: recorderUIManager,
                            modelContext: modelContext,
                            transcriptionModelManager: transcriptionModelManager
                        )
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Export all settings, or choose specific categories when importing a backup.")
            }

            Section("Save Targets") {
                LabeledContent("Save Targets") {
                    Button("Manage") {
                        isShowingSaveTargets = true
                    }
                }
            }

            Section("Diagnostics") {
                DiagnosticsSettingsView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                DispatchQueue.main.async {
                    hasCompletedOnboardingV2 = false
                }
            }
        } message: {
            Text("You'll see the introduction screens again the next time you launch the app.")
        }
        .alert("Restart Diktilo to Apply Language", isPresented: $showLanguageRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your language change will take full effect after you quit and reopen Diktilo.")
        }
        .sheet(isPresented: $isShowingSaveTargets) {
            NavigationStack {
                SaveTargetsSettingsView()
                    .navigationTitle("Save Targets")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingSaveTargets = false }
                        }
                    }
            }
            .frame(minWidth: 500, minHeight: 420)
        }
    }

}

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
