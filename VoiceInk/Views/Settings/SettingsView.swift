import SwiftUI
import Cocoa
import Carbon.HIToolbox
import LaunchAtLogin

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = true
    @AppStorage(AppAppearancePreference.userDefaultsKey) private var appAppearancePreference = AppAppearancePreference.system
    @AppStorage(AppLanguagePreference.userDefaultsKey) private var appLanguagePreference = AppLanguagePreference.systemValue
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage("RecorderDestinationHUDEnabled") private var destinationHUDEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isRealtimeEnabled) private var globalRealtimeEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isTextFormattingEnabled) private var globalTextFormattingEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isAIEnhancementEnabled) private var globalAIEnhancementEnabled = true
    @AppStorage(PasteMethod.userDefaultsKey) private var pasteMethodRawValue = PasteMethod.standard.rawValue
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage(ClipboardManager.autoCopyEnabledKey) private var autoCopyTranscription = true
    @State private var showResetOnboardingAlert = false
    @State private var showLanguageRestartAlert = false
    @State private var isShowingSaveTargets = false
    @State private var isMiddleClickExpanded = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(.accentColor)
                    Text("Start and cancel recording shortcuts are configured on the Modes screen.")
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

            Section("Additional Shortcuts") {
                LabeledContent("Paste Last Transcription (Original)") {
                    ShortcutRecorder(action: .pasteLastTranscription) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                    .controlSize(.small)
                }

                LabeledContent("Paste Last Transcription (Enhanced)") {
                    ShortcutRecorder(action: .pasteLastEnhancement) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                    .controlSize(.small)
                }

                LabeledContent("Retry Last Transcription") {
                    ShortcutRecorder(action: .retryLastTranscription) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                    .controlSize(.small)
                }

                ExpandableSettingsRow(
                    isExpanded: $isMiddleClickExpanded,
                    isEnabled: $recordingShortcutManager.isMiddleClickToggleEnabled,
                    label: "Middle-Click Recording"
                ) {
                    LabeledContent("Activation Delay") {
                        HStack {
                            TextField("", value: $recordingShortcutManager.middleClickActivationDelay, formatter: {
                                let formatter = NumberFormatter()
                                formatter.minimum = 0
                                return formatter
                            }())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            Text("ms")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section {
                Picker(selection: $pasteMethodRawValue) {
                    ForEach(PasteMethod.allCases) { method in
                        Text(method.displayName).tag(method.rawValue)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Paste Method")
                        InfoTip("Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly. Individual modes can override this.")
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: pasteMethodRawValue) { _, newValue in
                    guard let method = PasteMethod(rawValue: newValue) else {
                        pasteMethodRawValue = PasteMethod.standard.rawValue
                        return
                    }
                    PasteMethod.setCurrent(method)
                }

                Toggle(isOn: $autoCopyTranscription) {
                    HStack(spacing: 4) {
                        Text("Auto-copy Transcription")
                        InfoTip("Copy every completed transcription to the clipboard, regardless of the mode's destination — so it lands in a clipboard manager's history (e.g. Alfred). While on, the previous clipboard content is never restored after pasting.")
                    }
                }

                Toggle(isOn: $restoreClipboardAfterPaste) {
                    HStack(spacing: 4) {
                        Text("Keep Clipboard Content")
                        InfoTip("Diktilo temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay.")
                    }
                }
                .disabled(autoCopyTranscription)

                if autoCopyTranscription {
                    Text("Overridden while Auto-copy Transcription is on — the transcription stays on the clipboard.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if restoreClipboardAfterPaste && !autoCopyTranscription {
                    Picker("Restore Delay", selection: $clipboardRestoreDelay) {
                        Text("250ms").tag(0.25)
                        Text("500ms").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("4s").tag(4.0)
                        Text("5s").tag(5.0)
                    }
                }
            } header: {
                Text("Pasting (Global Defaults)")
            }

            Section("Transcription") {
                Toggle(isOn: $globalRealtimeEnabled) {
                    HStack(spacing: 4) {
                        Text("Real-time Streaming")
                        InfoTip("Stream audio to the transcription server while you speak. Falls back to batch transcription automatically when unavailable. Applies to every mode.")
                    }
                }

                Toggle(isOn: $globalTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text("Paragraph Formatting")
                        InfoTip("Break large blocks of transcribed text into paragraphs. Applies to every mode.")
                    }
                }

                Toggle(isOn: $globalAIEnhancementEnabled) {
                    HStack(spacing: 4) {
                        Text("AI Enhancement")
                        InfoTip("Master switch. Off = no mode enhances, regardless of per-mode setting. On = per-mode toggle decides. Useful for temporarily disabling all LLM calls without touching individual modes.")
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

                Button("Reset Onboarding") {
                    showResetOnboardingAlert = true
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
