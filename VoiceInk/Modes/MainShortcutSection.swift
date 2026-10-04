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

    static let defaultCancelShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    var body: some View {
        Section {
            // Stacked rather than a LabeledContent row: the shortcut is the
            // point of this screen and gets the full width of the section.
            VStack(alignment: .leading, spacing: 10) {
                Text("Start and Stop Recording")
                    .font(.system(size: 13, weight: .semibold))

                ShortcutRecorder(action: .primaryRecording, style: .prominent) {
                    recordingShortcutManager.primaryRecordingShortcut = .custom
                    recordingShortcutManager.updateShortcutStatus()
                }

                VStack(alignment: .leading, spacing: 4) {
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

                    Text(modeDescription(recordingShortcutManager.primaryRecordingShortcutMode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            // The main shortcut carries no mode of its own: it runs the
            // "default" mode unless an app or website trigger matches.
            LabeledContent {
                Picker(selection: mainShortcutModeBinding) {
                    if modeManager.getDefaultConfiguration() == nil {
                        Text("Last used mode").tag(UUID?.none)
                    }
                    ForEach(mainShortcutModeChoices) { config in
                        Text(config.name).tag(Optional(config.id))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .fixedSize()
            } label: {
                Text("Uses Mode")
                Text("When no app or website trigger matches.")
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

    private func modeDescription(_ mode: RecordingShortcutManager.Mode) -> LocalizedStringKey {
        switch mode {
        case .toggle: return "Press to start, press again to finish."
        case .pushToTalk: return "Hold while you speak, release to finish."
        case .hybrid: return "Tap to start and stop, or hold while you speak."
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
