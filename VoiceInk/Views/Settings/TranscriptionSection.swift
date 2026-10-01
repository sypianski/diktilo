import SwiftUI

/// Recording → Transcription: the languages you dictate in and how speech
/// becomes text, shared by every mode. The model itself is the first link of
/// AI Models → Model Order.
struct TranscriptionSection: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @AppStorage(GlobalTranscriptionSettings.Keys.isRealtimeEnabled) private var isRealtimeEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isTextFormattingEnabled) private var isTextFormattingEnabled = true

    @State private var languages = DictationLanguages.codes
    @State private var isAddingLanguage = false

    private enum RealtimeLimit {
        case none
        case unsupported
        case required
    }

    var body: some View {
        Section {
            LabeledContent {
                Button("Add Language…") { isAddingLanguage = true }
                    .popover(isPresented: $isAddingLanguage, arrowEdge: .trailing) {
                        DictationLanguagePicker(excluded: languages) { code in
                            isAddingLanguage = false
                            update(languages + [code])
                        }
                    }
            } label: {
                Text("Dictation Languages")
                Text(languagesNote)
            }

            ForEach(Array(languages.enumerated()), id: \.element) { index, code in
                languageRow(code, at: index)
            }

            if let model = transcriptionModelManager.currentTranscriptionModel {
                if model.provider == .nativeApple {
                    NativeAppleLanguageAssetControl(
                        localeIdentifier: DictationLanguages.effectiveLanguage(for: model),
                        isVisible: true
                    )
                }

                let unsupported = DictationLanguages.unsupportedLanguages(by: model)
                if !unsupported.isEmpty {
                    Text(String(
                        format: String(localized: "%1$@ doesn't transcribe %2$@. Put another model first in AI Models → Model Order."),
                        model.displayName,
                        unsupported.map(DictationLanguages.displayName(for:)).joined(separator: ", ")
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Accent.text)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: realtimeBinding) {
                HStack(spacing: 4) {
                    Text("Live Transcription (Streaming)")
                    InfoTip("Stream audio to the transcription server while you speak. Falls back to batch transcription automatically when unavailable. Applies to every mode.")
                }
                if let note = realtimeLimitNote {
                    Text(note)
                }
            }
            .disabled(realtimeLimit != .none)

            Toggle(isOn: $isTextFormattingEnabled) {
                HStack(spacing: 4) {
                    Text("Split Into Paragraphs")
                    InfoTip("Break large blocks of transcribed text into paragraphs. Applies to every mode.")
                }
            }
        } header: {
            Text("Transcription")
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictationLanguagesDidChange)) { _ in
            languages = DictationLanguages.codes
        }
    }

    // MARK: - Languages

    private var languagesNote: String {
        switch languages.count {
        case 0:
            return String(localized: "None chosen: the model recognizes the language you speak.")
        case 1:
            return String(localized: "The model transcribes in this language.")
        default:
            return String(localized: "The model recognizes which of these you speak. Models that can't (e.g. Apple Speech) use the first one.")
        }
    }

    private func languageRow(_ code: String, at index: Int) -> some View {
        HStack(spacing: 8) {
            Text(DictationLanguages.displayName(for: code))
                .foregroundStyle(AppTheme.Text.primary)

            Spacer(minLength: 8)

            Button {
                update(languages.filter { $0 != code })
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove Language")
            .accessibilityLabel(Text("Remove Language"))
        }
        .padding(.leading, 12)
        .contextMenu {
            Button("Move Up") { move(index, by: -1) }
                .disabled(index == 0)
            Button("Move Down") { move(index, by: 1) }
                .disabled(index == languages.count - 1)
            Divider()
            Button("Remove Language") { update(languages.filter { $0 != code }) }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard languages.indices.contains(target) else { return }
        var reordered = languages
        reordered.swapAt(index, target)
        update(reordered)
    }

    private func update(_ newLanguages: [String]) {
        DictationLanguages.codes = newLanguages
        languages = DictationLanguages.codes
        DictationLanguages.syncLegacySelectedLanguage(for: transcriptionModelManager.currentTranscriptionModel)
        whisperModelManager.whisperPrompt.updateTranscriptionPrompt()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    // MARK: - Live transcription

    // Same limits the pipeline applies (TranscriptionRealtimeSupport): the
    // switch shows what will actually happen with the current model.
    private var realtimeLimit: RealtimeLimit {
        guard let model = transcriptionModelManager.currentTranscriptionModel else { return .none }
        if !TranscriptionRealtimeSupport.isAvailable(for: model) { return .unsupported }
        if TranscriptionRealtimeSupport.isRequired(for: model) { return .required }
        return .none
    }

    private var realtimeBinding: Binding<Bool> {
        Binding(
            get: {
                switch realtimeLimit {
                case .unsupported: return false
                case .required: return true
                case .none: return isRealtimeEnabled
                }
            },
            set: { isRealtimeEnabled = $0 }
        )
    }

    private var realtimeLimitNote: String? {
        switch realtimeLimit {
        case .unsupported:
            return String(localized: "This model can't transcribe live; it transcribes the whole recording at the end.")
        case .required:
            return String(localized: "This model only works live.")
        case .none:
            return nil
        }
    }
}

/// Searchable list of the languages some model transcribes.
private struct DictationLanguagePicker: View {
    let excluded: [String]
    let onPick: (String) -> Void

    @State private var query = ""

    private var matches: [(code: String, name: String)] {
        let excludedBases = Set(excluded.map(DictationLanguages.baseCode))
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return DictationLanguages.selectableLanguages.filter { language in
            !excludedBases.contains(language.code)
                && (trimmed.isEmpty || language.name.localizedCaseInsensitiveContains(trimmed))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Languages", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)

            List(matches, id: \.code) { language in
                Button {
                    onPick(language.code)
                } label: {
                    Text(language.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 260, height: 320)
    }
}
