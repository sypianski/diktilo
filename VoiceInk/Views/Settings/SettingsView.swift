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
    @AppStorage("dashboardRecentTranscriptCount") private var dashboardRecentCount = 5
    @State private var showResetOnboardingAlert = false
    @State private var showLanguageRestartAlert = false
    @State private var isAdvancedExpanded = false

    // Only what concerns the app itself. Recording shortcut, pasting and save
    // targets live in Modes; transcription in AI Models; the bar in Recording.
    var body: some View {
        VStack(spacing: 0) {
            AppScreenHeader(title: "App") { EmptyView() }
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
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

}

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
