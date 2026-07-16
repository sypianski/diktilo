import Foundation

struct OutputProfileDraft {
    var id: UUID
    var name: String
    var icon: ModeIcon
    var appConfigs: [AppConfig]
    var websiteConfigs: [URLConfig]
    var triggerGroups: [ModeTriggerGroup]
    var triggerWords: [String]
    var isAIEnhancementEnabled: Bool
    var selectedPromptId: UUID?
    var useClipboardContext: Bool
    var useSelectedTextContext: Bool
    var useScreenCapture: Bool
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var outputMode: OutputMode
    var autoSendKey: AutoSendKey
    var customCommand: String
    var saveTargetID: UUID?
    var isDefault: Bool
    // Per-mode paste overrides (nil = use global Settings value).
    var pasteMethodOverride: String?
    var restoreClipboardOverride: Bool?
    var clipboardRestoreDelayOverride: Double?

    private var sourceConfig: OutputProfile?

    init(mode: ConfigurationMode, modeManager: OutputProfileManager) {
        switch mode {
        case .add:
            let inheritedConfig = modeManager.currentEffectiveConfiguration

            id = UUID()
            name = ""
            icon = .defaultIcon
            appConfigs = []
            websiteConfigs = []
            triggerGroups = []
            triggerWords = []
            isAIEnhancementEnabled = false
            selectedPromptId = inheritedConfig?.selectedPrompt.flatMap { UUID(uuidString: $0) }
            useClipboardContext = false
            useSelectedTextContext = false
            useScreenCapture = true
            selectedAIProvider = inheritedConfig?.selectedAIProvider
            selectedAIModel = inheritedConfig?.selectedAIModel
            outputMode = .paste
            autoSendKey = .none
            customCommand = inheritedConfig?.customCommand?.command ?? ""
            saveTargetID = nil
            isDefault = false
            pasteMethodOverride = nil
            restoreClipboardOverride = nil
            clipboardRestoreDelayOverride = nil
            sourceConfig = nil

        case .edit(let config):
            let latestConfig = modeManager.getConfiguration(with: config.id) ?? config
            id = latestConfig.id
            name = latestConfig.name
            icon = latestConfig.icon
            appConfigs = latestConfig.appConfigs ?? []
            websiteConfigs = latestConfig.urlConfigs ?? []
            triggerGroups = latestConfig.triggerGroups ?? []
            triggerWords = latestConfig.triggerWords
            isAIEnhancementEnabled = latestConfig.isAIEnhancementEnabled
            selectedPromptId = latestConfig.selectedPrompt.flatMap { UUID(uuidString: $0) }
            useClipboardContext = latestConfig.useClipboardContext
            useSelectedTextContext = latestConfig.useSelectedTextContext
            useScreenCapture = latestConfig.useScreenCapture
            selectedAIProvider = latestConfig.selectedAIProvider
            selectedAIModel = latestConfig.selectedAIModel
            outputMode = latestConfig.outputMode
            autoSendKey = latestConfig.autoSendKey
            customCommand = latestConfig.customCommand?.command ?? ""
            saveTargetID = latestConfig.saveTargetID
            isDefault = latestConfig.isDefault
            pasteMethodOverride = latestConfig.pasteMethodOverride
            restoreClipboardOverride = latestConfig.restoreClipboardOverride
            clipboardRestoreDelayOverride = latestConfig.clipboardRestoreDelayOverride
            sourceConfig = latestConfig
        }
    }

    var canSave: Bool {
        !name.isEmpty
    }

    mutating func applyAddModeDefaults(snapshot: ModeFormWarmupSnapshot) {
        let connectedProviders = snapshot.connectedAIProviders
        let inheritedProvider = selectedAIProvider.flatMap(AIProvider.init(rawValue:))
        let provider = inheritedProvider.flatMap { provider in
            connectedProviders.contains(provider) ? provider : nil
        } ?? connectedProviders.first

        selectedAIProvider = provider?.rawValue
        guard let provider, provider != .localCLI else {
            selectedAIModel = nil
            return
        }

        let availableModels = snapshot.availableModels(for: provider)
        if let selectedAIModel,
           !selectedAIModel.isEmpty,
           (availableModels.isEmpty || availableModels.contains(selectedAIModel)) {
            return
        }

        selectedAIModel = snapshot.selectedModel(for: provider)
    }

    mutating func ensurePromptSelection(firstPromptId: UUID?) {
        if isAIEnhancementEnabled && selectedPromptId == nil {
            selectedPromptId = firstPromptId
        }
    }

    mutating func applyOutputRules(canRespond: Bool) {
        if outputMode == .respond && !canRespond {
            outputMode = .paste
        }

        if !outputMode.usesPasteOptions {
            autoSendKey = .none
            pasteMethodOverride = nil
            restoreClipboardOverride = nil
            clipboardRestoreDelayOverride = nil
        }

        if outputMode == .respond {
            isDefault = false
        }
    }

    func makeConfig(mode: ConfigurationMode) -> OutputProfile {
        let savedAutoSendKey: AutoSendKey = outputMode.usesPasteOptions ? autoSendKey : .none
        let savedIsDefault = outputMode == .respond ? false : isDefault
        let savedCustomCommand = makeCustomCommand()
        let savedSaveTargetID = outputMode == .saveTarget ? saveTargetID : nil
        // Paste overrides only meaningful when outputMode == .paste; otherwise strip.
        let savedPasteMethod = outputMode.usesPasteOptions ? pasteMethodOverride : nil
        let savedRestoreClipboard = outputMode.usesPasteOptions ? restoreClipboardOverride : nil
        let savedClipboardRestoreDelay = outputMode.usesPasteOptions ? clipboardRestoreDelayOverride : nil

        switch mode {
        case .add:
            return OutputProfile(
                id: id,
                name: name,
                icon: icon,
                appConfigs: appConfigs.isEmpty ? nil : appConfigs,
                urlConfigs: websiteConfigs.isEmpty ? nil : websiteConfigs,
                triggerGroups: triggerGroups.isEmpty ? nil : triggerGroups,
                triggerWords: triggerWords,
                isAIEnhancementEnabled: isAIEnhancementEnabled,
                selectedPrompt: selectedPromptId?.uuidString,
                useClipboardContext: useClipboardContext,
                useSelectedTextContext: useSelectedTextContext,
                useScreenCapture: useScreenCapture,
                selectedAIProvider: selectedAIProvider,
                selectedAIModel: selectedAIModel,
                outputMode: outputMode,
                autoSendKey: savedAutoSendKey,
                customCommand: savedCustomCommand,
                saveTargetID: savedSaveTargetID,
                isDefault: savedIsDefault,
                pasteMethodOverride: savedPasteMethod,
                restoreClipboardOverride: savedRestoreClipboard,
                clipboardRestoreDelayOverride: savedClipboardRestoreDelay
            )

        case .edit(let config):
            var updatedConfig = sourceConfig ?? config
            updatedConfig.name = name
            updatedConfig.icon = icon
            updatedConfig.appConfigs = appConfigs.isEmpty ? nil : appConfigs
            updatedConfig.urlConfigs = websiteConfigs.isEmpty ? nil : websiteConfigs
            updatedConfig.triggerGroups = triggerGroups.isEmpty ? nil : triggerGroups
            updatedConfig.triggerWords = OutputProfile.normalizedTriggerWords(triggerWords)
            updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            updatedConfig.useClipboardContext = useClipboardContext
            updatedConfig.useSelectedTextContext = useSelectedTextContext
            updatedConfig.useScreenCapture = useScreenCapture
            updatedConfig.selectedAIProvider = selectedAIProvider
            updatedConfig.selectedAIModel = selectedAIModel
            updatedConfig.outputMode = outputMode
            updatedConfig.autoSendKey = savedAutoSendKey
            updatedConfig.customCommand = savedCustomCommand
            updatedConfig.saveTargetID = savedSaveTargetID
            updatedConfig.isDefault = savedIsDefault
            updatedConfig.pasteMethodOverride = savedPasteMethod
            updatedConfig.restoreClipboardOverride = savedRestoreClipboard
            updatedConfig.clipboardRestoreDelayOverride = savedClipboardRestoreDelay
            return updatedConfig
        }
    }

    private func makeCustomCommand() -> OutputCommand? {
        let command = OutputCommand(command: customCommand)
        return command.trimmedCommand == nil ? nil : command
    }
}
