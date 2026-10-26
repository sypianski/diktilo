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
    @AppStorage(AdvancedFeature.fileTranscription.defaultsKey) private var fileTranscriptionEnabled = AdvancedFeature.defaultValue
    @State private var showResetOnboardingAlert = false
    @State private var isAdvancedExpanded = false
    @State private var languageNeedsRestart = false

    // Only what concerns the app itself. Recording shortcut, pasting and save
    // targets live in Modes; transcription in AI Models; the bar in Recording.
    var body: some View {
        VStack(spacing: 0) {
            AppScreenHeader(title: "App") { EmptyView() }
            settingsForm
        }
    }

    private var settingsForm: some View {
        ScrollViewReader { proxy in
            Form {
                languageAndAppearanceSection
                startupSection
                advancedSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onAppear { scrollToPendingSection(proxy) }
            .onReceive(NotificationCenter.default.publisher(for: .showSettingsSection)) { _ in
                scrollToPendingSection(proxy)
            }
        }
        .alert("Show Introduction Again", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Show Again") {
                DispatchQueue.main.async {
                    hasCompletedOnboardingV2 = false
                }
            }
        } message: {
            Text("You'll see the introduction screens again the next time you launch the app.")
        }
    }

    /// The Help menu's "Report a Bug…" opens this screen at Diagnostics, which
    /// lives inside the folded Advanced section: unfold it first, then scroll
    /// once the section has its final height.
    private func scrollToPendingSection(_ proxy: ScrollViewProxy) {
        guard let anchor = SettingsAnchor.consumePending() else { return }
        switch anchor {
        case .diagnostics:
            withAnimation(.easeInOut(duration: 0.2)) { isAdvancedExpanded = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
        }
    }

    // MARK: - Language and appearance

    private var languageAndAppearanceSection: some View {
        Section("Language & Appearance") {
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
                languageNeedsRestart = true
            }

            if languageNeedsRestart {
                restartBar
            }

            if UserAddressForm.appliesToCurrentLanguage {
                LabeledContent {
                    Picker("", selection: $userAddressForm) {
                        ForEach(UserAddressForm.allCases) { form in
                            Text(form.displayName).tag(form)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } label: {
                    Text("Grammatical gender")
                    Text("Used where Diktilo addresses you in Polish.")
                }
                .padding(.leading, 16)
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
        }
    }

    /// Replaces the old alert: it does not interrupt work and offers the restart itself.
    private var restartBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundColor(AppTheme.Accent.text)

            Text("Language change takes effect after restart.")
                .font(.system(size: 12))

            Spacer(minLength: 8)

            Button("Restart") {
                AppRestarter.relaunch()
            }
            .buttonStyle(.amberProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Accent.fillSubtle)
        )
    }

    // MARK: - Startup, help, data

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)

            LaunchAtLogin.Toggle(String(localized: "Launch at Login"))
        }
    }

    // MARK: - Advanced

    /// Folded by default: backup, diagnostics, help and rarely changed options.
    /// The groups are VStacks (not nested Sections), because the whole block is
    /// one row of the grouped Form.
    private var advancedSection: some View {
        Section {
            ExpandableSettingsRow(
                title: "Advanced",
                isExpanded: $isAdvancedExpanded,
                isEnabled: nil,
                summary: "Backup, diagnostics, help and intro, and optional features.",
                statusNote: nil
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    optionalFeaturesGroup
                    dashboardGroup
                    helpGroup
                    dataGroup
                    diagnosticsGroup
                }
            }
        }
    }

    private func advancedGroupTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    /// Switching it off only hides the sidebar item; history and settings stay.
    private var optionalFeaturesGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            advancedGroupTitle("Optional features")

            Toggle(isOn: $fileTranscriptionEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Transcribe Files")
                        InfoTip("Hiding it only removes the item from the sidebar. Your history and settings are kept, and opening an audio or video file in Diktilo turns it back on.")
                    }
                    Text("Transcribe audio and video files. The result is saved in History.")
                        .settingsDescription()
                }
            }
        }
    }

    private var dashboardGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            advancedGroupTitle("Dashboard")

            Picker(selection: $dashboardRecentCount) {
                Text("3").tag(3)
                Text("5").tag(5)
                Text("8").tag(8)
                Text("10").tag(10)
            } label: {
                Text("Recent Transcripts on Dashboard")
                Text("How many recent transcriptions the dashboard shows at the top.")
            }
            .pickerStyle(.menu)
        }
    }

    private var helpGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            advancedGroupTitle("Help")

            LabeledContent("Diktilo Tour") {
                Button("Show Tour") {
                    AppTour.show()
                }
            }

            LabeledContent {
                Button("Show Again") {
                    showResetOnboardingAlert = true
                }
            } label: {
                Text("Introduction")
                Text("Replay the first-launch screens.")
            }
        }
    }

    private var dataGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            advancedGroupTitle("Data")

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
        }
    }

    private var diagnosticsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            advancedGroupTitle("Diagnostics")

            DiagnosticsSettingsView()
        }
        .id(SettingsAnchor.diagnostics)
    }
}

/// Where a deep link into Settings should land. The Help menu sets it before
/// navigating; the screen reads it once it appears (or when it is already open).
@MainActor
enum SettingsAnchor: String {
    case diagnostics

    private static var pending: SettingsAnchor?

    static func request(_ anchor: SettingsAnchor) {
        pending = anchor
        _ = WindowManager.shared.showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": ViewType.settings.rawValue])
            NotificationCenter.default.post(name: .showSettingsSection, object: nil)
        }
    }

    static func consumePending() -> SettingsAnchor? {
        defer { pending = nil }
        return pending
    }
}

extension Notification.Name {
    static let showSettingsSection = Notification.Name("showSettingsSection")
}

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
