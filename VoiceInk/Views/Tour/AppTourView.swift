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
// Never opens by itself: the onboarding summary offers it, and it stays
// available from Settings and Help → Diktilo Tour.

enum AppTour {
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
    case modes
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
            progressHeader
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

            AppTourStage(step: step)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                ))
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(AppTheme.Surface.subtle)

            Divider()

            AppTourCaption(step: step, onOpen: open)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 560)
        .background(AppTheme.Surface.window)
    }

    /// "Step 2 of 4", one segment per step, and the close button. The close
    /// button is on every step (Esc too), so the last step can be dismissed
    /// like the others.
    private var progressHeader: some View {
        HStack(spacing: 12) {
            Text(String(
                format: String(localized: "Step %lld of %lld"),
                step.rawValue + 1,
                AppTourStep.allCases.count
            ))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(AppTourStep.allCases) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? AppTheme.Accent.primary : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel(Text("Close"))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
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

    /// Closes the tour (it is a sheet over the main window) and opens a screen.
    private func open(_ destination: ViewType) {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": destination.rawValue]
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
    let onOpen: (ViewType) -> Void

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
                Button("Set Recording Shortcut") { onOpen(.modes) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            // Hidden advanced features: say where to switch them on.
            if step == .modes && !AdvancedFeature.modes.isEnabled() {
                Button("Open Shortcuts and Modes") { onOpen(.modes) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            if step == .settings && !AdvancedFeature.fileTranscription.isEnabled() {
                Button("Open App settings") { onOpen(.settings) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }

        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .record: return "Record in any app"
        case .modes: return "Modes"
        case .history: return "History and clipboard"
        case .settings: return "Where to change things"
        }
    }

    private var message: String {
        switch step {
        case .record:
            guard let shortcut = TourFacts.primaryShortcut else {
                return String(localized: "You don't have a recording shortcut yet. Set one in Shortcuts and Modes to start recording from any app.")
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
            let place = TourFacts.isNotchRecorder
                ? String(localized: "at the top of the screen, by the notch")
                : String(localized: "at the bottom of the screen")
            let bar = String(
                format: String(localized: "While you record, this bar appears %@. The round button on the left finishes, %@."),
                place,
                TourFacts.cancelPhrase
            )
            return how + " " + TourFacts.activeOutputSentence + " " + bar
        case .modes:
            let modesText = String(localized: "A mode sets whether AI rewrites the text and where the result goes. Finish with a mode's shortcut to use that mode.")
            // Users who already had modes keep them on; everyone else is told where to find them.
            return AdvancedFeature.modes.isEnabled()
                ? modesText
                : modesText + " " + String(localized: "Modes and Save Targets are off by default. Turn them on in Shortcuts and Modes.")
        case .history:
            return TourFacts.isAutoCopyEnabled
                ? String(localized: "Every recording is saved in History and copied to the clipboard. The copy button on a transcript copies it again.")
                : String(localized: "Every recording is saved in History. The copy button on a transcript copies it again.")
        case .settings:
            let settingsText = String(localized: "Everything is in the sidebar. To see this guide again, choose Help → Diktilo Tour.")
            return AdvancedFeature.fileTranscription.isEnabled()
                ? settingsText
                : settingsText + " " + String(localized: "Transcribing files is off by default. Turn on Transcribe Files in App → Advanced.")
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
            case .modes: ModesStage()
            case .history: HistoryStage()
            case .settings: SettingsStage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The user's actual recording shortcut as keycaps, with the recording bar
/// it opens right underneath.
private struct RecordStage: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ShortcutPreviewView(shortcut: TourFacts.primaryShortcut)
                Text(TourFacts.recordingMode.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.Surface.controlActive))
            }
            RecorderBarStage()
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

            PerforationRule(color: RecorderPalette(surface).rule)

            HStack(spacing: 6) {
                ForEach(FinishDestinationBindings.hudItems().prefix(3)) { item in
                    DestinationChip(label: item.label, shortcut: item.shortcutDisplay)
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
        .scaleEffect(1.1)
        .frame(height: 40 + RecorderHUDMetrics.bandHeight + 8)
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
                Text("No modes yet — add one in Shortcuts and Modes.")
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

/// A sample transcript and where it lands: History, and the clipboard when
/// auto-copy is on. Example text only.
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

            VStack(spacing: 14) {
                target(icon: ViewType.history.icon, title: ViewType.history.title)
                if TourFacts.isAutoCopyEnabled {
                    target(icon: "list.clipboard.fill", title: "Clipboard")
                }
            }
        }
    }

    private func target(icon: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(AppTheme.Accent.primary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// The whole sidebar, one sentence per item, so the guide covers the app.
private struct SettingsStage: View {
    @AppStorage(AdvancedFeature.fileTranscription.defaultsKey) private var fileTranscriptionEnabled = AdvancedFeature.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(ViewType.visiblePrimaryItems(fileTranscriptionEnabled: fileTranscriptionEnabled) + ViewType.secondaryItems) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.Accent.primary)
                        .frame(width: 18)

                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)

                    Text(item.tourSentence)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension ViewType {
    var tourSentence: LocalizedStringKey {
        switch self {
        case .dashboard: return "Latest transcripts and first steps."
        case .modes: return "Recording shortcut and modes: what happens to the text."
        case .transcribeAudio: return "Transcribe a ready audio file."
        case .history: return "Every recording, ready to copy again."
        case .dictionary: return "Your words and replacements."
        case .models: return "Speech recognition and text improvement."
        case .audio: return "Microphone, languages and recording bar."
        case .settings: return "Language, appearance and advanced options."
        }
    }
}
