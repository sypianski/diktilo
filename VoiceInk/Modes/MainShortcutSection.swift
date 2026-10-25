import SwiftUI
import Carbon.HIToolbox

/// Top block of the Modes screen: the shortcut that starts and stops
/// recording, how it behaves, and which mode it runs. It is the one setting
/// every user needs, so it is always expanded; the rarer recording shortcuts
/// (second shortcut, cancel, middle click) sit in a disclosure underneath.
/// Per-mode finish shortcuts stay with the mode they belong to.
struct MainShortcutSection: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @ObservedObject var modeManager: OutputProfileManager

    @State private var hasCancelShortcut: Bool = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelResetID = 0
    @State private var isMiddleClickExpanded = false
    @State private var isMoreExpanded = false
    @State private var shortcutRevision = 0

    static let defaultCancelShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    var body: some View {
        Section {
            // The shortcut is the point of this screen: its recorder and the
            // press/hold behaviour share a row, and one sentence with the real
            // keys says what happens.
            HStack(alignment: .center, spacing: 16) {
                ShortcutRecorder(action: .primaryRecording, style: .prominent) {
                    recordingShortcutManager.primaryRecordingShortcut = .custom
                    recordingShortcutManager.updateShortcutStatus()
                }

                Picker(selection: $recordingShortcutManager.primaryRecordingShortcutMode) {
                    ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.vertical, 4)

            // The main shortcut carries no mode of its own: it runs the
            // "default" mode unless an app or website trigger matches.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(shortcutSentence)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Picker(selection: mainShortcutModeBinding) {
                    if modeManager.getDefaultConfiguration() == nil {
                        Text("Last used mode").tag(UUID?.none)
                    }
                    ForEach(mainShortcutModeChoices) { config in
                        Text(config.name).tag(Optional(config.id))
                    }
                } label: {
                    Text("Mode")
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("The mode the main shortcut runs when no app or website trigger matches.")
            }

            DisclosureGroup("More Recording Shortcuts", isExpanded: $isMoreExpanded) {
                secondShortcutRow
                cancelShortcutRow
                middleClickRow
            }
        } header: {
            Text("Main Shortcut")
        } footer: {
            // Fixed panel keys — not rebindable, so they're spelled out here.
            Text("While recording: ⌥1–⌥0 switches the mode, ⌘↩ finishes in the current mode, and a mode's finish shortcut finishes in that mode.")
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { _ in
            shortcutRevision += 1
        }
    }

    /// "Press ⌃⌥ Space, speak, press again": what the shortcut does right now.
    private var shortcutSentence: String {
        _ = shortcutRevision
        guard let shortcut = ShortcutStore.shortcut(for: .primaryRecording) else {
            return String(localized: "Set a shortcut to start recording from any app.")
        }
        let keys = shortcut.displayString
        switch recordingShortcutManager.primaryRecordingShortcutMode {
        case .toggle:
            return String(format: String(localized: "Press %@, speak, press again."), keys)
        case .pushToTalk:
            return String(format: String(localized: "Hold %@ while you speak, release to finish."), keys)
        case .hybrid:
            return String(format: String(localized: "Tap %@ to start and stop, or hold it while you speak."), keys)
        }
    }

    /// Respond modes answer in the recorder panel instead of delivering text,
    /// so they can't sit behind the main shortcut.
    private var mainShortcutModeChoices: [OutputProfile] {
        modeManager.enabledConfigurations.filter { $0.outputMode != .respond }
    }

    private var mainShortcutModeBinding: Binding<UUID?> {
        Binding(
            get: { modeManager.getDefaultConfiguration()?.id },
            set: { newValue in
                guard let newValue else { return }
                modeManager.setAsDefault(configId: newValue)
            }
        )
    }

    @ViewBuilder
    private var secondShortcutRow: some View {
        if recordingShortcutManager.secondaryRecordingShortcut != .none {
            LabeledContent("Second Shortcut") {
                HStack(spacing: 8) {
                    modePicker(binding: $recordingShortcutManager.secondaryRecordingShortcutMode)
                    ShortcutRecorder(action: .secondaryRecording) {
                        recordingShortcutManager.secondaryRecordingShortcut = .custom
                        recordingShortcutManager.updateShortcutStatus()
                    }
                    .controlSize(.small)
                    Button {
                        withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .none }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove second shortcut")
                }
            }
        } else {
            LabeledContent("Second Shortcut") {
                Button("Add Second Shortcut") {
                    withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .custom }
                }
                .controlSize(.small)
            }
        }
    }

    private var cancelShortcutRow: some View {
        LabeledContent {
            HStack(spacing: 8) {
                ShortcutRecorder(
                    action: .cancelRecorder,
                    defaultShortcut: Self.defaultCancelShortcut
                ) {
                    hasCancelShortcut = true
                }
                .id(cancelResetID)
                .controlSize(.small)

                if hasCancelShortcut {
                    Button {
                        ShortcutStore.setShortcut(nil, for: .cancelRecorder)
                        hasCancelShortcut = false
                        cancelResetID += 1
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                }
            }
        } label: {
            Text("Cancel Recording")
            if !hasCancelShortcut {
                Text("Default: press Esc twice.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let action = notification.object as? ShortcutAction, action == .cancelRecorder else { return }
            hasCancelShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
        }
    }

    // Another way to start recording, so it lives with the shortcuts that
    // start recording rather than with the utility shortcuts.
    private var middleClickRow: some View {
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

    private func modePicker(binding: Binding<RecordingShortcutManager.Mode>) -> some View {
        Picker(selection: binding) {
            ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
        .fixedSize()
        .controlSize(.small)
    }
}
