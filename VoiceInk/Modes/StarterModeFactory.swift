import AppKit
import Foundation

enum StarterModeFactory {
    static let defaultTranscriptionModelName = "parakeet-tdt-0.6b-v3"

    static func install(
        kinds: [StarterModeKind],
        provider: AIProvider,
        modelName: String?,
        transcriptionModelName: String = defaultTranscriptionModelName,
        isRealtimeTranscriptionEnabled: Bool = true,
        selectedLanguage: String = "auto"
    ) {
        let manager = OutputProfileManager.shared
        let requestedKinds = Set(kinds)

        // Transcription is global now - seed it once from the onboarding choice.
        GlobalTranscriptionSettings.modelName = transcriptionModelName
        GlobalTranscriptionSettings.isRealtimeEnabled = isRealtimeTranscriptionEnabled
        GlobalTranscriptionSettings.language = selectedLanguage
        GlobalTranscriptionSettings.isTextFormattingEnabled = true

        let starterConfigs = StarterModeCatalog.templates
            .filter { requestedKinds.contains($0.kind) }
            .map {
                makeConfig(
                    from: $0,
                    provider: provider,
                    modelName: modelName
                )
            }

        let nonStarterConfigs = manager.configurations
            .filter { !StarterModeCatalog.ids.contains($0.id) }
            .map { config -> OutputProfile in
                var config = config
                if starterConfigs.contains(where: \.isDefault) {
                    config.isDefault = false
                }
                return config
            }

        manager.replaceConfigurations(starterConfigs + nonStarterConfigs)

        for config in starterConfigs where config.isDefault {
            ShortcutStore.removeShortcutStorage(for: .profile(config.id))
        }

        if let defaultConfig = starterConfigs.first(where: \.isDefault) {
            manager.setActiveConfiguration(defaultConfig)
        }
    }

    /// The default "Paste" mode, built without seeding the global transcription
    /// settings the way `install` does during onboarding.
    static func makeDefaultMode() -> OutputProfile? {
        guard let template = StarterModeCatalog.templates.first(where: { $0.kind == .clean }) else {
            return nil
        }

        return makeConfig(from: template, provider: nil, modelName: nil)
    }

    static func isInstalled(kind: StarterModeKind) -> Bool {
        guard let template = StarterModeCatalog.templates.first(where: { $0.kind == kind }) else {
            return false
        }

        return OutputProfileManager.shared.configurations.contains { $0.id == template.id }
    }

    private static func makeConfig(
        from template: StarterModeTemplate,
        provider: AIProvider?,
        modelName: String?
    ) -> OutputProfile {
        OutputProfile(
            id: template.id,
            name: template.name,
            icon: template.icon,
            isAIEnhancementEnabled: template.usesAIEnhancement,
            selectedPrompt: template.promptId?.uuidString,
            useSelectedTextContext: template.useSelectedTextContext,
            useScreenCapture: template.useScreenCapture,
            selectedAIProvider: template.usesAIEnhancement ? provider?.rawValue : nil,
            selectedAIModel: template.usesAIEnhancement ? (modelName ?? provider?.defaultModel) : nil,
            outputMode: template.outputMode,
            autoSendKey: .none,
            isEnabled: true,
            isDefault: template.isDefault
        )
    }
}
