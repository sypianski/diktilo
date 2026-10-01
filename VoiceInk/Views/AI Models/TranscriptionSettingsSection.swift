import SwiftUI

/// App-wide transcription settings: one model, language and pipeline shared by
/// every mode. Sits at the top of AI Models, above the catalog it picks from.
struct TranscriptionSettingsSection: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @AppStorage(GlobalTranscriptionSettings.Keys.isRealtimeEnabled) private var isRealtimeEnabled = true
    @AppStorage(GlobalTranscriptionSettings.Keys.isTextFormattingEnabled) private var isTextFormattingEnabled = true

    private enum RealtimeLimit {
        case none
        case unsupported
        case required
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Transcription")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text("Used by every mode.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .padding(.bottom, 6)

            row {
                Text("Transcription Model")
            } content: {
                modelPicker
            }

            PerforationRule()

            row {
                Text("Language")
            } content: {
                LanguageSelectionView(
                    transcriptionModelManager: transcriptionModelManager,
                    displayMode: .inline,
                    whisperPrompt: whisperModelManager.whisperPrompt
                )
            }

            PerforationRule()

            row {
                HStack(spacing: 4) {
                    Text("Live Transcription (Streaming)")
                    InfoTip("Stream audio to the transcription server while you speak. Falls back to batch transcription automatically when unavailable. Applies to every mode.")
                }
            } content: {
                Toggle("Live Transcription (Streaming)", isOn: realtimeBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(realtimeLimit != .none)
            }

            if let note = realtimeLimitNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .padding(.bottom, 8)
            }

            PerforationRule()

            row {
                HStack(spacing: 4) {
                    Text("Split Into Paragraphs")
                    InfoTip("Break large blocks of transcribed text into paragraphs. Applies to every mode.")
                }
            } content: {
                Toggle("Split Into Paragraphs", isOn: $isTextFormattingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.card))
    }

    // MARK: - Model

    /// Only models that can transcribe right now: downloaded local models,
    /// cloud models with an API key, custom models. The current model stays in
    /// the list even if it became unusable, so the picker never shows blank.
    private var selectableModels: [any TranscriptionModel] {
        var models = transcriptionModelManager.usableModels.filter {
            transcriptionModelManager.isAvailableOnCurrentOS($0)
        }
        if let current = transcriptionModelManager.currentTranscriptionModel,
           !models.contains(where: { $0.name == current.name }) {
            models.insert(current, at: 0)
        }
        return models
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { transcriptionModelManager.currentTranscriptionModel?.name ?? "" },
            set: { name in
                guard let model = selectableModels.first(where: { $0.name == name }) else { return }
                transcriptionModelManager.setDefaultTranscriptionModel(model)
            }
        )
    }

    @ViewBuilder
    private var modelPicker: some View {
        if selectableModels.isEmpty {
            Text("Download a model below first")
                .foregroundStyle(AppTheme.Text.secondary)
        } else {
            Picker("Transcription Model", selection: modelSelection) {
                if transcriptionModelManager.currentTranscriptionModel == nil {
                    Text("No model selected").tag("")
                }
                ForEach(selectableModels, id: \.name) { model in
                    Text(model.displayName).tag(model.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Only downloaded local models, cloud providers with an API key and your custom models are listed.")
        }
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

    // MARK: - Layout

    private func row<Label: View, Content: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            label()
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.Text.primary)

            Spacer(minLength: 12)

            content()
        }
        .padding(.vertical, 10)
    }
}
