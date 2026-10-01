import SwiftUI

/// How text reaches the target app — the global defaults behind every mode
/// that pastes. A mode can override the paste method and clipboard restore in
/// its own "Custom paste settings".
struct ModesPastingSection: View {
    @AppStorage(PasteMethod.userDefaultsKey) private var pasteMethodRawValue = PasteMethod.standard.rawValue
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage(ClipboardManager.autoCopyEnabledKey) private var autoCopyTranscription = true
    @AppStorage("AppendTrailingSpace") private var appendTrailingSpace = true

    var body: some View {
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
            Text("Pasting and Clipboard")
        } footer: {
            if autoCopyTranscription {
                Text("Keep Clipboard Content is off while every transcription is copied — the transcription stays on the clipboard.")
            }
        }
    }
}
