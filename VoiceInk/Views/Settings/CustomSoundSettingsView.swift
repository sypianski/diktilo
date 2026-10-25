import SwiftUI
import UniformTypeIdentifiers

struct CustomSoundSettingsView: View {
    @StateObject private var customSoundManager = CustomSoundManager.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private enum SoundMenuSelection: Hashable {
        case none
        case builtIn(CustomSoundManager.BuiltInSound)
        case custom
    }

    var body: some View {
        LabeledContent("Sounds") {
            HStack(spacing: 14) {
                soundControl(for: .start, title: "Start")
                soundControl(for: .stop, title: "Stop")
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func currentName(for type: CustomSoundManager.SoundType) -> String {
        switch customSoundManager.soundSelection(for: type) {
        case .none:
            return String(localized: "None")
        case .builtIn(let sound):
            return sound.displayName
        case .custom:
            return customSoundManager.getSoundDisplayName(for: type) ?? String(localized: "Custom")
        }
    }

    /// "Start [Sound 1 ▾] ▶": the file picker and the reset live in the menu.
    @ViewBuilder
    private func soundControl(for type: CustomSoundManager.SoundType, title: LocalizedStringKey) -> some View {
        let selection = customSoundManager.soundSelection(for: type)
        let isCustom = selection.isCustom
        let fileName = customSoundManager.getSoundDisplayName(for: type)

        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)

            Menu {
                Picker("Sound", selection: soundSelectionBinding(for: type)) {
                    Text("None").tag(SoundMenuSelection.none)

                    ForEach(CustomSoundManager.BuiltInSound.allCases) { sound in
                        Text(sound.displayName).tag(SoundMenuSelection.builtIn(sound))
                    }

                    if isCustom || fileName != nil {
                        Text(String(format: String(localized: "Custom: %@"), fileName ?? String(localized: "Custom")))
                            .tag(SoundMenuSelection.custom)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()

                Button("Custom File…") {
                    selectSound(for: type)
                }

                if !customSoundManager.isDefaultSelection(for: type) {
                    Button("Restore Default") {
                        if !selection.isEnabled || isCustom {
                            customSoundManager.resetSoundToDefault(for: type)
                        } else {
                            customSoundManager.selectBuiltInSound(type.defaultBuiltInSound, for: type)
                        }
                    }
                }
            } label: {
                Text(currentName(for: type))
                    .lineLimit(1)
                    .frame(maxWidth: 96, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Select sound")

            Button {
                if type == .start {
                    SoundManager.shared.playStartSound()
                } else {
                    SoundManager.shared.playStopSound()
                }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!selection.isEnabled)
            .help("Test")
        }
    }

    private func soundSelectionBinding(for type: CustomSoundManager.SoundType) -> Binding<SoundMenuSelection> {
        Binding(
            get: {
                switch customSoundManager.soundSelection(for: type) {
                case .none:
                    return .none
                case .builtIn(let sound):
                    return .builtIn(sound)
                case .custom:
                    return .custom
                }
            },
            set: { selection in
                switch selection {
                case .none:
                    customSoundManager.selectNoSound(for: type)
                case .builtIn(let sound):
                    customSoundManager.selectBuiltInSound(sound, for: type)
                case .custom:
                    customSoundManager.useCustomSound(for: type)
                }
            }
        )
    }

    private func selectSound(for type: CustomSoundManager.SoundType) {
        let panel = NSOpenPanel()
        panel.title = String(format: String(localized: "Choose %@ Sound"), type.rawValue.capitalized)
        panel.message = String(localized: "Select an audio file")
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mp3,
            UTType.wav,
            UTType.aiff
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let result = customSoundManager.setCustomSound(url: url, for: type)
            if case .failure(let error) = result {
                alertTitle = "Invalid Audio File"
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

#Preview {
    CustomSoundSettingsView()
        .frame(width: 400)
        .padding()
}
