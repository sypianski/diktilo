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
    @AppStorage(UserAddressForm.userDefaultsKey) private var userAddressForm = UserAddressForm.masculine
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage("RecorderDestinationHUDEnabled") private var destinationHUDEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isRealtimeEnabled) private var globalRealtimeEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isTextFormattingEnabled) private var globalTextFormattingEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isAIEnhancementEnabled) private var globalAIEnhancementEnabled = true
    @AppStorage(PasteMethod.userDefaultsKey) private var pasteMethodRawValue = PasteMethod.standard.rawValue
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage(ClipboardManager.autoCopyEnabledKey) private var autoCopyTranscription = true
    @AppStorage("dashboardRecentTranscriptCount") private var dashboardRecentCount = 5
    @AppStorage("AppendTrailingSpace") private var appendTrailingSpace = true
    @ObservedObject private var saveTargetManager = SaveTargetManager.shared
    @State private var showResetOnboardingAlert = false
    @State private var showLanguageRestartAlert = false
    @State private var isShowingSaveTargets = false
    @State private var isAdvancedExpanded = false

    // Order follows how often each setting is needed: the recording shortcut
    // first, set-once housekeeping last behind "Advanced".
    var body: some View {
        VStack(spacing: 0) {
            AppScreenHeader(title: "Settings") { EmptyView() }
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            RecordingShortcutsSection()

            Section("Save Targets") {
                LabeledContent {
                    Button("Manage…") {
                        isShowingSaveTargets = true
                    }
                } label: {
                    Text(saveTargetsSummary)
                    Text("Files, URL schemes, shell commands or Notaro — each can have its own finish shortcut.")
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
                        Text("Copy Every Transcription to Clipboard")
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

                Toggle(isOn: $appendTrailingSpace) {
                    HStack(spacing: 4) {
                        Text("Add Space After Paste")
                        InfoTip("Add a trailing space after pasted transcription output.")
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                if autoCopyTranscription {
                    Text("Keep Clipboard Content is off while every transcription is copied — the transcription stays on the clipboard.")
                }
            }

            Section("Transcription") {
                LabeledContent {
                    Button("Change…") {
                        navigate(to: .models)
                    }
                } label: {
                    Text("Model and Language")
                    Text(transcriptionModelManager.currentTranscriptionModel?.displayName
                         ?? String(localized: "No model selected"))
                }

                Toggle(isOn: $globalRealtimeEnabled) {
                    HStack(spacing: 4) {
                        Text("Live Transcription (Streaming)")
                        InfoTip("Stream audio to the transcription server while you speak. Falls back to batch transcription automatically when unavailable. Applies to every mode.")
                    }
                }

                Toggle(isOn: $globalTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text("Split Into Paragraphs")
                        InfoTip("Break large blocks of transcribed text into paragraphs. Applies to every mode.")
                    }
                }

                Toggle(isOn: $globalAIEnhancementEnabled) {
                    HStack(spacing: 4) {
                        Text("AI Enhancement")
                        InfoTip("Master switch. Off = no mode enhances, regardless of per-mode setting. On = per-mode toggle decides. Useful for temporarily disabling all LLM calls without touching individual modes.")
                    }
                }
            }

            Section("Recording Panel") {
                Picker("Panel Style", selection: $recorderUIManager.recorderPanelStyle) {
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
                        Text("Shortcut Hints While Recording")
                        InfoTip("Show the finish shortcuts of your modes and save targets under the recording bar.")
                    }
                }
            }

            Section("Utility Shortcuts") {
                ForEach(ShortcutAction.globalUtilityActions, id: \.storageName) { action in
                    LabeledContent(action.displayName) {
                        ShortcutRecorder(action: action) {
                            recordingShortcutManager.updateShortcutStatus()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("General") {
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

                if UserAddressForm.appliesToCurrentLanguage {
                    Picker(selection: $userAddressForm) {
                        ForEach(UserAddressForm.allCases) { form in
                            Text(form.displayName).tag(form)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Grammatical gender")
                            InfoTip("Used where Diktilo addresses you in Polish.")
                        }
                    }
                    .pickerStyle(.menu)
                }

                Picker("Appearance", selection: $appAppearancePreference) {
                    ForEach(AppAppearancePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appAppearancePreference) { _, newValue in
                    newValue.apply()
                }

                Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)

                LaunchAtLogin.Toggle(String(localized: "Launch at Login"))

                LabeledContent("Diktilo Tour") {
                    Button("Show Tour") {
                        AppTour.show()
                    }
                }
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                    advancedContent
                }
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


    @ViewBuilder
    private var advancedContent: some View {
        Picker(selection: $dashboardRecentCount) {
            Text("3").tag(3)
            Text("5").tag(5)
            Text("8").tag(8)
            Text("10").tag(10)
        } label: {
            HStack(spacing: 4) {
                Text("Recent Transcripts on Dashboard")
                InfoTip("How many recent transcriptions the dashboard shows at the top.")
            }
        }
        .pickerStyle(.menu)

        LabeledContent {
            HStack(spacing: 8) {
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
        } label: {
            Text("Backup")
            Text("Export all settings, or choose specific categories when importing a backup.")
        }

        LabeledContent("Onboarding") {
            Button("Reset Onboarding") {
                showResetOnboardingAlert = true
            }
        }

        DiagnosticsSettingsView()
    }

    private var saveTargetsSummary: String {
        let names = saveTargetManager.targets.map(\.name)
        guard !names.isEmpty else { return String(localized: "No save targets yet") }
        return names.joined(separator: ", ")
    }

    private func navigate(to destination: ViewType) {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": destination.rawValue]
        )
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
