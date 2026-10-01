import SwiftUI
import Carbon.HIToolbox

// MARK: - AppTour
//
// First-run tour: a short slideshow showing where things are. Each step pairs
// an enlarged replica built from the app's real components (recorder button,
// visualizer, HUD chips, sidebar rows, the user's own shortcut and modes) with
// one or two sentences. A slideshow rather than coach marks on the live UI,
// because most of what needs explaining — the recording bar, global shortcuts,
// the clipboard — lives outside the main window.
//
// Shown once after onboarding (`hasSeenAppTourV1`), and on demand from
// Settings and Help → Diktilo Tour.

enum AppTour {
    static let hasSeenKey = "hasSeenAppTourV1"
    static let showRequested = Notification.Name("AppTourShowRequested")

    /// Brings the main window forward (it hosts the sheet), then asks it to
    /// present the tour.
    @MainActor
    static func show() {
        _ = WindowManager.shared.showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: showRequested, object: nil)
        }
    }
}

enum AppTourStep: Int, CaseIterable, Identifiable {
    case record
    case recorderBar
    case modes
    case models
    case history
    case settings

    var id: Int { rawValue }
}

struct AppTourView: View {
    let onClose: () -> Void

    @State private var step: AppTourStep
    @State private var forward = true

    init(startAt step: AppTourStep = .record, onClose: @escaping () -> Void) {
        _step = State(initialValue: step)
        self.onClose = onClose
    }

    private var isLast: Bool { step == AppTourStep.allCases.last }

    var body: some View {
        VStack(spacing: 0) {
            AppTourStage(step: step)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                ))
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(AppTheme.Surface.subtle)

            Divider()

            AppTourCaption(step: step, onOpenSettings: openSettings)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560)
        .background(AppTheme.Surface.window)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Skip Tour", action: onClose)
                .focusEffectDisabled()
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)

            Spacer()

            HStack(spacing: 6) {
                ForEach(AppTourStep.allCases) { item in
                    Circle()
                        .fill(item == step ? AppTheme.Accent.primary : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(String(
                format: String(localized: "Step %lld of %lld"),
                step.rawValue + 1,
                AppTourStep.allCases.count
            )))

            Spacer()

            if step != AppTourStep.allCases.first {
                Button("Back", action: goBack)
            }

            Button(isLast ? "Start Dictating" : "Next") {
                isLast ? onClose() : advance()
            }
            .buttonStyle(.amberProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private func advance() {
        guard let next = AppTourStep(rawValue: step.rawValue + 1) else { return }
        forward = true
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    private func goBack() {
        guard let previous = AppTourStep(rawValue: step.rawValue - 1) else { return }
        forward = false
        withAnimation(.easeInOut(duration: 0.25)) { step = previous }
    }

    private func openSettings() {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": ViewType.modes.rawValue]
        )
        onClose()
    }
}

// MARK: - Live data the steps describe

private enum TourFacts {
    static var primaryShortcut: Shortcut? {
        ShortcutStore.shortcut(for: .primaryRecording)
    }

    static var recordingMode: RecordingShortcutManager.Mode {
        let raw = UserDefaults.standard.string(forKey: "primaryRecordingShortcutMode") ?? ""
        return RecordingShortcutManager.Mode(rawValue: raw) ?? .toggle
    }

    /// Without a custom cancel shortcut the recorder cancels on a double Esc.
    static var cancelPhrase: String {
        if let shortcut = ShortcutStore.shortcut(for: .cancelRecorder) {
            return String(format: String(localized: "%@ cancels"), shortcut.displayString)
        }
        return String(localized: "Esc pressed twice cancels")
    }

    static var isAutoCopyEnabled: Bool {
        ClipboardManager.isAutoCopyEnabled
    }

    /// What happens to the text when a recording ends in the active mode.
    @MainActor
    static var activeOutputSentence: String {
        switch OutputProfileManager.shared.currentEffectiveConfiguration?.outputMode {
        case .paste, .none:
            return String(localized: "The text is pasted where your cursor is.")
        case .copy:
            return String(localized: "The text lands on the clipboard.")
        case .editWindow:
            return String(localized: "The text opens in the edit window.")
        case .respond, .customCommand, .saveTarget:
            return String(localized: "The active mode decides where the text goes.")
        }
    }

    static var isNotchRecorder: Bool {
        RecorderPanelStyle.stored == .notch
    }

    @MainActor
    static var modes: [OutputProfile] {
        Array(OutputProfileManager.shared.enabledConfigurations.prefix(4))
    }
}

// MARK: - Caption

private struct AppTourCaption: View {
    let step: AppTourStep
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .bold))

            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if step == .record && TourFacts.primaryShortcut == nil {
                Button("Set Recording Shortcut", action: onOpenSettings)
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            // The full explainer, not a link away: this choice decides where
            // recordings go, so the tour shows it in whole.
            if step == .models {
                LocalOrKeyExplainer()
                    .padding(.top, 4)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .record: return "Record in any app"
        case .recorderBar: return "The recording bar"
        case .modes: return "Modes"
        case .models: return "Local model or API key"
        case .history: return "History and clipboard"
        case .settings: return "Where to change things"
        }
    }

    private var message: String {
        switch step {
        case .record:
            guard let shortcut = TourFacts.primaryShortcut else {
                return String(localized: "You don't have a recording shortcut yet. Set one in Keyboard Shortcuts to start recording from any app.")
            }
            let keys = shortcut.displayString
            let how: String
            switch TourFacts.recordingMode {
            case .toggle:
                how = String(format: String(localized: "Press %@ in any app, speak, then press it again."), keys)
            case .pushToTalk:
                how = String(format: String(localized: "Hold %@ in any app and speak. Let go to finish."), keys)
            case .hybrid:
                how = String(format: String(localized: "Tap %@ to start and tap again to finish, or hold it while you speak."), keys)
            }
            return how + " " + TourFacts.activeOutputSentence
        case .recorderBar:
            let place = TourFacts.isNotchRecorder
                ? String(localized: "at the top of the screen, by the notch")
                : String(localized: "at the bottom of the screen")
            return String(
                format: String(localized: "While you record, this bar appears %@. The round button on the left finishes, %@. The shortcuts underneath finish the recording and send the text to a specific place."),
                place,
                TourFacts.cancelPhrase
            )
        case .modes:
            return String(localized: "A mode sets whether AI rewrites the text and where the result goes: pasted, copied, opened in the edit window or saved to a file. Finish with a mode's shortcut to use that mode. While the bar is open, ⌥1…⌥0 switches modes.")
        case .models:
            return String(localized: "Diktilo transcribes with a local model or through an outside provider with an API key.")
        case .history:
            return TourFacts.isAutoCopyEnabled
                ? String(localized: "Every transcription is copied to the clipboard and saved in History. The dashboard shows the latest ones; the copy button on a card copies it again.")
                : String(localized: "Every transcription is saved in History. The dashboard shows the latest ones; the copy button on a card copies it again.")
        case .settings:
            return String(localized: "The recording shortcut and modes are in Keyboard Shortcuts, the microphone and the bar's look in Recording, language and appearance in App. To see this tour again, choose Help → Diktilo Tour.")
        }
    }
}

// MARK: - Stage

private struct AppTourStage: View {
    let step: AppTourStep

    var body: some View {
        ZStack {
            switch step {
            case .record: RecordStage()
            case .recorderBar: RecorderBarStage()
            case .modes: ModesStage()
            case .models: ModelsStage()
            case .history: HistoryStage()
            case .settings: SettingsStage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The user's actual recording shortcut as big keycaps.
private struct RecordStage: View {
    var body: some View {
        VStack(spacing: 16) {
            ShortcutPreviewView(shortcut: TourFacts.primaryShortcut)
            Text(TourFacts.recordingMode.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppTheme.Surface.controlActive))
        }
    }
}

/// An enlarged replica of the mini recorder while recording, built from the
/// same button, visualizer and HUD chips the real panel uses.
private struct RecorderBarStage: View {
    @ObservedObject private var modeManager = OutputProfileManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private let surface: RecorderSurface = TourFacts.isNotchRecorder ? .notch : .panel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RecorderRecordButton(recordingState: .recording, action: {})
                    .allowsHitTesting(false)
                    .padding(.leading, 10)
                Spacer(minLength: 0)
                AudioVisualizer(
                    audioMeter: AudioMeter(averagePower: 0.55, peakPower: 0.7),
                    color: RecorderPalette(surface).waveform,
                    isActive: true
                )
                Spacer(minLength: 0)
                RecorderToggleButton(
                    isEnabled: true,
                    icon: modeManager.currentEffectiveConfiguration?.icon.value ?? "square.grid.2x2",
                    action: {}
                )
                .allowsHitTesting(false)
                .frame(width: 22)
                .padding(.trailing, 12)
            }
            .frame(height: 40)

            if surface == .panel {
                PerforationRule()
            } else {
                Divider().background(Color.white.opacity(0.10))
            }

            HStack(spacing: 6) {
                ForEach(FinishDestinationBindings.hudItems().prefix(3)) { item in
                    DestinationChip(item: item)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: RecorderHUDMetrics.bandHeight)
        }
        .frame(width: 340)
        .environment(\.recorderSurface, surface)
        .background(surface == .panel ? AppTheme.Palette.paper : Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(surface == .panel ? AppTheme.Palette.rule : .clear, lineWidth: 1)
        )
        .environment(\.colorScheme, surface == .notch ? .dark : colorScheme)
        .scaleEffect(1.35)
        .accessibilityElement()
        .accessibilityLabel(Text("Recording bar"))
    }
}

/// The user's own enabled modes: icon, name, output and finish shortcut.
private struct ModesStage: View {
    var body: some View {
        let modes = TourFacts.modes
        VStack(spacing: 8) {
            if modes.isEmpty {
                Text("No modes yet — add one in Keyboard Shortcuts.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(modes) { mode in
                    ModeRow(mode: mode)
                }
            }
        }
        .frame(width: 400)
    }

    private struct ModeRow: View {
        let mode: OutputProfile

        var body: some View {
            HStack(spacing: 10) {
                Group {
                    switch mode.icon.kind {
                    case .symbol: Image(systemName: mode.icon.value)
                    case .emoji: Text(mode.icon.value)
                    }
                }
                .font(.system(size: 14))
                .frame(width: 22)

                Text(mode.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Label(mode.outputMode.displayName, systemImage: mode.outputMode.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(ShortcutStore.shortcut(for: .profile(mode.id))?.displayString ?? "—")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppCardBackground(cornerRadius: 10))
        }
    }
}

/// A sample dashboard card and the clipboard it lands on. Example text only.
private struct HistoryStage: View {
    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today, 10:42")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Example: the meeting moves to Thursday at ten, please bring the draft.")
                    .font(.system(size: 13))
                    .lineLimit(2)
            }
            .padding(14)
            .frame(width: 280, alignment: .leading)
            .background(AppCardBackground(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Accent.primary)
                    .padding(8)
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(AppTheme.Accent.primary)
                Text("Clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The model the advisor picks for this Mac; the local-vs-key explainer
/// itself sits in the caption, where it has room to grow.
private struct ModelsStage: View {
    private let recommendation = ModelAdvisor.currentRecommendation()

    var body: some View {
        ModelAdvisorSummary(recommendation: recommendation)
            .padding(16)
            .background(AppCardBackground(cornerRadius: 12))
            .padding(.horizontal, 28)
    }
}

/// The real sidebar rows where things are changed, plus where the tour lives.
private struct SettingsStage: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 3) {
                ForEach([ViewType.modes, .audio, .settings]) { item in
                    SidebarItemButton(viewType: item, isSelected: item == .modes, action: {})
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 190)
            .padding(8)
            .background(AppCardBackground(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text("Help")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Diktilo Tour")
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .selectedContentBackgroundColor))
                    )
                    .foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
            }
            .padding(.top, 6)
        }
    }
}
