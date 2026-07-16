import SwiftUI
import Carbon.HIToolbox

/// Global (non-per-mode) shortcuts and utilities shown at the top of the Modes
/// screen. Everything that is NOT tied to a specific mode lives here:
///
///   • Start shortcuts (primary + optional secondary) — the shared entry point
///     for recording. Per-mode shortcuts finish; these start.
///   • Cancel / Middle-click / Vim / Sako — mode-agnostic recorder utilities.
///   • Paste Last / Retry Last — history-driven actions on the last transcript.
///
/// Presented as a `DisclosureGroup` so the top of the screen stays compact by
/// default; expand to configure. Content mirrors what used to live in the
/// "Shortcuts" / "Additional Shortcuts" / "Pasting" sections of the app
/// Settings screen before Phase 3.
struct ModesGlobalSection: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @AppStorage(PasteMethod.userDefaultsKey) private var pasteMethodRawValue = PasteMethod.standard.rawValue
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0

    @State private var isExpanded: Bool = false
    @State private var hasCancelShortcut: Bool = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelResetID = 0
    @State private var isMiddleClickExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Form {
                startShortcutsSection
                additionalShortcutsSection
                pastingSection
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
                Text("start, cancel, paste last, retry")
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

            LabeledContent("Open Vim Editor") {
                ShortcutRecorder(action: .openVimEditor) {
                    recordingShortcutManager.updateShortcutStatus()
                }
                .controlSize(.small)
            }

            LabeledContent("Open Sako") {
                ShortcutRecorder(action: .openWorek) {
                    recordingShortcutManager.updateShortcutStatus()
                }
                .controlSize(.small)
            }

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
    }

    // MARK: - Pasting (global defaults; per-mode overrides live in the mode editor)

    private var pastingSection: some View {
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

            Toggle(isOn: $restoreClipboardAfterPaste) {
                HStack(spacing: 4) {
                    Text("Keep Clipboard Content")
                    InfoTip("Diktilo temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay.")
                }
            }

            if restoreClipboardAfterPaste {
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
