import SwiftUI

/// "Model for This Mac": what the Mac is, which model fits it and the
/// language the user dictates in, and a one-click way to switch to it.
struct ModelAdvisorCard: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var fluidAudioModelManager: FluidAudioModelManager
    // Read so the card follows language changes made in the section above.
    @AppStorage(GlobalTranscriptionSettings.Keys.language) private var selectedLanguage = "en"

    /// Shows the cloud providers when local models are a poor fit (Intel).
    var onShowCloudProviders: (() -> Void)?

    @State private var hardware = MacHardwareProfile.current()
    @State private var isStartingDownload = false

    private var language: String {
        ModelAdvisor.dictationLanguage(
            selected: ModelAdvisor.explicitSelectedLanguage == nil ? nil : selectedLanguage,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    private var recommendation: ModelRecommendation {
        ModelAdvisor.recommend(for: hardware, language: language)
    }

    private var recommendedModel: (any TranscriptionModel)? {
        transcriptionModelManager.allAvailableModels.first { $0.name == recommendation.modelName }
    }

    private var isCurrent: Bool {
        transcriptionModelManager.currentTranscriptionModel?.name == recommendation.modelName
    }

    private var isUsable: Bool {
        transcriptionModelManager.usableModels.contains { $0.name == recommendation.modelName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Model for This Mac")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text(ModelAdvisor.hardwareSummary(hardware))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.secondary)

                Text(String(format: String(localized: "Dictation language: %@"), ModelAdvisor.languageName(language)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .padding(.bottom, 10)

            PerforationRule()

            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: String(localized: "Recommended: %@"), ModelAdvisor.displayName(forModelNamed: recommendation.modelName)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text(recommendation.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let alternative = recommendation.alternativeModelName,
                   let alternativeReason = recommendation.alternativeReason {
                    Text(String(format: String(localized: "Alternative: %@. %@"), ModelAdvisor.displayName(forModelNamed: alternative), alternativeReason))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    action

                    if recommendation.suggestsCloud, let onShowCloudProviders {
                        Button("Set Up a Cloud Model", action: onShowCloudProviders)
                            .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.card))
        .onAppear { hardware = MacHardwareProfile.current() }
    }

    // MARK: - Action

    @ViewBuilder
    private var action: some View {
        if isCurrent {
            Label("You're using the recommended model", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.primary)
        } else if let fraction = downloadFraction {
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(AppTheme.Accent.primary)
                    .frame(width: 140)
                Text("Downloading…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
        } else if isStartingDownload {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
        } else if isUsable {
            Button("Use This Model") { use(named: recommendation.modelName) }
                .buttonStyle(.amberProminent)
                .controlSize(.small)
        } else if let model = recommendedModel, isDownloadable(model) {
            Button("Download and Use") { downloadAndUse(model) }
                .buttonStyle(.amberProminent)
                .controlSize(.small)
        }
    }

    private func isDownloadable(_ model: any TranscriptionModel) -> Bool {
        model is FluidAudioModel || model is WhisperModel
    }

    /// Same weighting as DownloadProgressView: Whisper models with a Core ML
    /// encoder download in two halves.
    private var downloadFraction: Double? {
        guard let model = recommendedModel else { return nil }
        if let fluidModel = model as? FluidAudioModel {
            return fluidAudioModelManager.downloadStatus(for: fluidModel)?.fractionCompleted
        }
        if model is WhisperModel {
            let progress = whisperModelManager.downloadProgress
            guard let main = progress[model.name + "_main"] else { return nil }
            let hasCoreML = !model.name.contains("q5") && !model.name.contains("q8")
            return hasCoreML ? (main * 0.5) + ((progress[model.name + "_coreml"] ?? 0) * 0.5) : main
        }
        return nil
    }

    private func downloadAndUse(_ model: any TranscriptionModel) {
        isStartingDownload = true
        Task { @MainActor in
            if let fluidModel = model as? FluidAudioModel {
                await fluidAudioModelManager.downloadFluidAudioModel(fluidModel)
            } else if let whisperModel = model as? WhisperModel {
                await whisperModelManager.downloadModel(whisperModel)
            }
            isStartingDownload = false
            use(named: model.name)
        }
    }

    /// Switches to the model; when the user never chose a language, also sets
    /// the one the advice was based on, so the model isn't told "English".
    private func use(named name: String) {
        guard let model = transcriptionModelManager.usableModels.first(where: { $0.name == name }) else { return }
        transcriptionModelManager.setDefaultTranscriptionModel(model)

        guard ModelAdvisor.explicitSelectedLanguage == nil,
              let code = model.supportedLanguages.keys.first(where: { ModelAdvisor.baseCode($0) == language }) else {
            return
        }
        selectedLanguage = code
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}

/// One line of advice for places without download controls (onboarding, tour).
struct ModelAdvisorSummary: View {
    let recommendation: ModelRecommendation
    var showsHardware = true

    private let hardware = MacHardwareProfile.cached

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsHardware {
                Text(ModelAdvisor.hardwareSummary(hardware))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Accent.text)
                Text(String(format: String(localized: "Recommended for this Mac: %@"), ModelAdvisor.displayName(forModelNamed: recommendation.modelName)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)
            }

            Text(recommendation.reason)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
