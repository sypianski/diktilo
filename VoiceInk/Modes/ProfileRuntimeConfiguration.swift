import Foundation

struct TranscriptionRuntimeConfiguration {
    let profile: OutputProfile?
    let model: any TranscriptionModel
    let language: String
    let isRealtimeEnabled: Bool
    /// Usable models after `model` in the fallback chain, tried in order when it fails.
    var fallbackModels: [any TranscriptionModel] = []

    var metadata: (name: String?, emoji: String?) {
        guard let profile, profile.isEnabled else {
            return (nil, nil)
        }
        return (profile.name, profile.icon.value)
    }

    var requestContext: TranscriptionRequestContext {
        TranscriptionRequestContext(
            language: language,
            prompt: model.provider == .whisper ? UserDefaults.standard.string(forKey: "TranscriptionPrompt") : nil
        )
    }

    /// Same language and prompt, adapted to a fallback model of the chain.
    func requestContext(forFallback fallback: any TranscriptionModel) -> TranscriptionRequestContext {
        TranscriptionRequestContext(
            language: DictationLanguages.effectiveLanguage(for: fallback),
            prompt: fallback.provider == .whisper ? UserDefaults.standard.string(forKey: "TranscriptionPrompt") : nil
        )
    }
}

struct TranscriptionFormattingConfiguration {
    let profile: OutputProfile?
    let isTextFormattingEnabled: Bool
}

struct EnhancementRuntimeConfiguration {
    let profile: OutputProfile?
    let isEnabled: Bool
    let prompt: CustomPrompt?
    let provider: AIProvider?
    let modelName: String?
    let useClipboardContext: Bool
    let useSelectedTextContext: Bool
    let useScreenCaptureContext: Bool

    /// The same request sent to another provider/model (fallback chain).
    func replacing(provider: AIProvider, modelName: String?) -> EnhancementRuntimeConfiguration {
        EnhancementRuntimeConfiguration(
            profile: profile,
            isEnabled: isEnabled,
            prompt: prompt,
            provider: provider,
            modelName: modelName,
            useClipboardContext: useClipboardContext,
            useSelectedTextContext: useSelectedTextContext,
            useScreenCaptureContext: useScreenCaptureContext
        )
    }

    func replacingPrompt(_ prompt: CustomPrompt) -> EnhancementRuntimeConfiguration {
        EnhancementRuntimeConfiguration(
            profile: profile,
            isEnabled: true,
            prompt: prompt,
            provider: provider,
            modelName: modelName,
            useClipboardContext: useClipboardContext,
            useSelectedTextContext: useSelectedTextContext,
            useScreenCaptureContext: useScreenCaptureContext
        )
    }
}

struct OutputRuntimeConfiguration {
    let profile: OutputProfile?
    let outputMode: OutputMode
    let autoSendKey: AutoSendKey
    let customCommand: OutputCommand?
    let saveTargetID: UUID?
}

/// Resolves the four runtime configurations for a recording.
///
/// Transcription (model / language / realtime / paragraph formatting) is now
/// **global** - see `GlobalTranscriptionSettings`. Only AI enhancement and
/// output destination vary per `OutputProfile`; the profile is still threaded
/// through so history metadata (name / icon) reflects the active profile.
@MainActor
enum ProfileRuntimeResolver {
    static func transcriptionConfiguration(
        profile: OutputProfile? = nil,
        transcriptionModelManager: TranscriptionModelManager
    ) -> TranscriptionRuntimeConfiguration? {
        let profile = profile ?? OutputProfileManager.shared.currentEffectiveConfiguration
        let chain = transcriptionModelManager.usableModelsInChainOrder()
        let model = chain.first ?? resolvedModel(
            named: GlobalTranscriptionSettings.modelName,
            transcriptionModelManager: transcriptionModelManager
        )

        guard let model else { return nil }
        let fallbackModels = chain.filter { $0.name != model.name }

        let realtimeEnabled = GlobalTranscriptionSettings.isRealtimeEnabled
        let language = DictationLanguages.effectiveLanguage(for: model)

        return TranscriptionRuntimeConfiguration(
            profile: profile,
            model: model,
            language: language,
            isRealtimeEnabled: TranscriptionRealtimeSupport.isEnabled(for: model, modeValue: realtimeEnabled),
            fallbackModels: fallbackModels
        )
    }

    static func transcriptionFormattingConfiguration(profile: OutputProfile? = nil) -> TranscriptionFormattingConfiguration {
        let profile = profile ?? OutputProfileManager.shared.currentEffectiveConfiguration

        return TranscriptionFormattingConfiguration(
            profile: profile,
            isTextFormattingEnabled: GlobalTranscriptionSettings.isTextFormattingEnabled
        )
    }

    static func currentEnhancementConfiguration(
        profile: OutputProfile? = nil,
        enhancementService: AIEnhancementService,
        aiService: AIService
    ) -> EnhancementRuntimeConfiguration {
        let profile = profile ?? OutputProfileManager.shared.currentEffectiveConfiguration
        let prompt = resolvedPrompt(
            promptId: profile?.selectedPrompt,
            enhancementService: enhancementService
        )
        let provider = resolvedProvider(
            providerName: profile?.selectedAIProvider,
            aiService: aiService
        )
        let modelName = resolvedEnhancementModelName(
            provider: provider,
            configuredModelName: profile?.selectedAIModel,
            aiService: aiService
        )

        // The mode alone decides; there is no app-wide master switch any more.
        let isEnabled = profile?.isAIEnhancementEnabled ?? false

        return EnhancementRuntimeConfiguration(
            profile: profile,
            isEnabled: isEnabled,
            prompt: prompt,
            provider: provider,
            modelName: modelName,
            useClipboardContext: profile?.useClipboardContext ?? false,
            useSelectedTextContext: profile?.useSelectedTextContext ?? true,
            useScreenCaptureContext: profile?.useScreenCapture ?? false
        )
    }

    static func outputConfiguration(profile: OutputProfile? = nil) -> OutputRuntimeConfiguration {
        let profile = profile ?? OutputProfileManager.shared.currentEffectiveConfiguration

        return OutputRuntimeConfiguration(
            profile: profile,
            outputMode: profile?.outputMode ?? .paste,
            autoSendKey: profile?.autoSendKey ?? .none,
            customCommand: profile?.customCommand,
            saveTargetID: profile?.saveTargetID
        )
    }

    /// Last resort when nothing in the fallback chain is usable.
    private static func resolvedModel(
        named modelName: String?,
        transcriptionModelManager: TranscriptionModelManager
    ) -> (any TranscriptionModel)? {
        if let modelName,
           let model = transcriptionModelManager.usableModels.first(where: { $0.name == modelName }) {
            return model
        }

        return transcriptionModelManager.usableModels.first
    }

    private static func resolvedPrompt(
        promptId: String?,
        enhancementService: AIEnhancementService
    ) -> CustomPrompt? {
        guard let promptId,
              let uuid = UUID(uuidString: promptId) else {
            return nil
        }

        return enhancementService.allPrompts.first { $0.id == uuid }
    }

    private static func resolvedProvider(
        providerName: String?,
        aiService: AIService
    ) -> AIProvider? {
        if let providerName,
           let provider = AIProvider(rawValue: providerName),
           aiService.connectedProviders.contains(provider) {
            return provider
        }

        return aiService.connectedProviders.first
    }

    private static func resolvedEnhancementModelName(
        provider: AIProvider?,
        configuredModelName: String?,
        aiService: AIService
    ) -> String? {
        guard let provider else { return nil }

        if provider == .localCLI {
            return nil
        }

        let models = aiService.availableModels(for: provider)
        if let configuredModelName,
           !configuredModelName.isEmpty,
           (models.isEmpty || models.contains(configuredModelName)) {
            return configuredModelName
        }

        if let firstModel = models.first {
            return firstModel
        }

        return provider.defaultModel
    }
}
