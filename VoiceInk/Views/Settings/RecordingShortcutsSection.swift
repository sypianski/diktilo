import SwiftUI
import Carbon.HIToolbox

/// The shortcuts that drive recording — start/stop (primary + optional
/// secondary) and cancel. First section of Settings, always expanded: it is
/// the one setting every user needs. Per-mode finish shortcuts stay on the
/// Modes screen, next to the mode they belong to.
struct RecordingShortcutsSection: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager

    @State private var hasCancelShortcut: Bool = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelResetID = 0
    @State private var isMiddleClickExpanded = false

    static let defaultCancelShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    modePicker(binding: $recordingShortcutManager.primaryRecordingShortcutMode)
                    ShortcutRecorder(action: .primaryRecording) {
                        recordingShortcutManager.primaryRecordingShortcut = .custom
                        recordingShortcutManager.updateShortcutStatus()
                    }
                }
            } label: {
                Text("Start and Stop Recording")
                    .font(.system(size: 13, weight: .semibold))
                Text(modeDescription(recordingShortcutManager.primaryRecordingShortcutMode))
            }

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
            }

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

            // Another way to start recording, so it lives with the shortcuts
            // that start recording rather than with the utility shortcuts.
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
        } header: {
            HStack {
                Text("Recording Shortcut")
                Spacer()
                if recordingShortcutManager.secondaryRecordingShortcut == .none {
                    Button("Add Second Shortcut") {
                        withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .custom }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
        } footer: {
            // Fixed panel keys — not rebindable, so they're spelled out here.
            Text("While recording: ⌥1–⌥0 switches the mode, ⌘↩ finishes in the current mode, and a mode's finish shortcut finishes in that mode.")
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
