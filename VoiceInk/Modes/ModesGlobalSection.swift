import SwiftUI
import Carbon.HIToolbox

/// Global (non-per-mode) recording shortcuts shown at the top of the Modes
/// screen — only what is tied to the recording flow itself:
///
///   • Start shortcuts (primary + optional secondary) — the shared entry point
///     for recording. Per-mode shortcuts finish; these start.
///   • Cancel — mode-agnostic recorder utility.
///
/// History-driven actions (paste last, retry last), middle-click recording and
/// the global pasting defaults live in the app Settings screen.
///
/// Presented as a `DisclosureGroup` so the top of the screen stays compact by
/// default; expand to configure.
struct ModesGlobalSection: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager

    @State private var isExpanded: Bool = false
    @State private var hasCancelShortcut: Bool = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelResetID = 0

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Form {
                startShortcutsSection
                additionalShortcutsSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "keyboard.fill")
                    .foregroundColor(.secondary)
                Text("Global Shortcuts")
                    .font(.system(size: 14, weight: .semibold))
                Text("start, cancel")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, isExpanded ? 4 : 0)
    }

    // MARK: - Start shortcuts

    private var startShortcutsSection: some View {
        Section("Start Recording") {
            LabeledContent("Primary Shortcut") {
                HStack(spacing: 8) {
                    Spacer()
                    shortcutModePicker(binding: $recordingShortcutManager.primaryRecordingShortcutMode)
                    ShortcutRecorder(action: .primaryRecording) {
                        recordingShortcutManager.primaryRecordingShortcut = .custom
                        recordingShortcutManager.updateShortcutStatus()
                    }
                    .controlSize(.small)
                }
            }

            if recordingShortcutManager.secondaryRecordingShortcut != .none {
                LabeledContent("Secondary Shortcut") {
                    HStack(spacing: 8) {
                        Spacer()
                        shortcutModePicker(binding: $recordingShortcutManager.secondaryRecordingShortcutMode)
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
                    }
                }
            } else {
                Button("Add Second Shortcut") {
                    withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .custom }
                }
            }
        }
    }

    // MARK: - Additional shortcuts

    private var additionalShortcutsSection: some View {
        Section("Recorder Utilities") {
            LabeledContent("Cancel Recording") {
                HStack(spacing: 8) {
                    ShortcutRecorder(
                        action: .cancelRecorder,
                        defaultShortcut: Self.defaultCancelRecordingShortcut
                    ) {
                        hasCancelShortcut = true
                    }
                    .id(cancelResetID)
                    .controlSize(.small)

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
            .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
                guard let action = notification.object as? ShortcutAction, action == .cancelRecorder else { return }
                hasCancelShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
            }
        }
    }

    // MARK: - Helpers

    private func shortcutModePicker(binding: Binding<RecordingShortcutManager.Mode>) -> some View {
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

    private static let defaultCancelRecordingShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )
}
