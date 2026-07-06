import Foundation

extension OutputProfileManager {
    func migratedOutputProfilesData(for configKey: String) -> Data? {
        let defaults = UserDefaults.standard
        let data: Data?
        if let existing = defaults.data(forKey: configKey) {
            data = existing
        } else if let legacyData = defaults.data(forKey: LegacyModeDataKey.configurations) {
            defaults.set(legacyData, forKey: configKey)
            data = legacyData
        } else {
            data = nil
        }

        if let data {
            seedGlobalTranscriptionFromLegacyIfNeeded(rawProfileData: data)
        }
        return data
    }

    /// One-time migration: transcription (model / language / realtime / formatting)
    /// used to live per-mode. Seed the new global settings from the previous
    /// default (or first) mode's stored values — but only for global keys that
    /// are still unset, so an explicit global choice is never overwritten.
    private func seedGlobalTranscriptionFromLegacyIfNeeded(rawProfileData: Data) {
        let defaults = UserDefaults.standard
        let flagKey = "didMigrateModesToGlobalTranscription"
        guard !defaults.bool(forKey: flagKey) else { return }
        defaults.set(true, forKey: flagKey)

        guard
            let array = try? JSONSerialization.jsonObject(with: rawProfileData) as? [[String: Any]],
            !array.isEmpty
        else { return }

        let source = array.first(where: { ($0["isDefault"] as? Bool) == true }) ?? array[0]

        if defaults.object(forKey: GlobalTranscriptionSettings.Keys.model) == nil,
           let model = source["selectedTranscriptionModelName"] as? String {
            GlobalTranscriptionSettings.modelName = model
        }
        if defaults.object(forKey: GlobalTranscriptionSettings.Keys.language) == nil,
           let language = source["selectedLanguage"] as? String {
            GlobalTranscriptionSettings.language = language
        }
        if defaults.object(forKey: GlobalTranscriptionSettings.Keys.isRealtimeEnabled) == nil,
           let realtime = source["isRealtimeTranscriptionEnabled"] as? Bool {
            GlobalTranscriptionSettings.isRealtimeEnabled = realtime
        }
        if defaults.object(forKey: GlobalTranscriptionSettings.Keys.isTextFormattingEnabled) == nil,
           let formatting = source["isTextFormattingEnabled"] as? Bool {
            GlobalTranscriptionSettings.isTextFormattingEnabled = formatting
        }
    }

    func migrateLoadedOutputProfilesIfNeeded() {
        var didChange = false

        for index in configurations.indices {
            var config = configurations[index]
            var changedConfig = false

            if config.selectedAIProvider == nil {
                config.selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
                changedConfig = true
            }

            if config.selectedAIModel == nil,
               let provider = config.selectedAIProvider {
                config.selectedAIModel = UserDefaults.standard.string(forKey: "\(provider)SelectedModel")
                changedConfig = true
            }

            if config.isAIEnhancementEnabled && config.selectedPrompt == nil {
                config.selectedPrompt = UserDefaults.standard.string(forKey: "selectedPromptId")
                changedConfig = true
            }

            if changedConfig {
                configurations[index] = config
                didChange = true
            }
        }

        if didChange {
            saveConfigurations()
        }

        migrateLegacyShortcutStorageIfNeeded()
    }

    private func migrateLegacyShortcutStorageIfNeeded() {
        let defaults = UserDefaults.standard

        for config in configurations {
            let oldShortcutKey = "\(LegacyModeDataKey.shortcutPrefix)\(config.id.uuidString)"
            let newShortcutKey = ShortcutAction.profile(config.id).userDefaultsKey

            if defaults.object(forKey: newShortcutKey) == nil,
               let oldShortcutData = defaults.data(forKey: oldShortcutKey) {
                defaults.set(oldShortcutData, forKey: newShortcutKey)
            }

            let oldClearedKey = "\(oldShortcutKey)_cleared"
            let newClearedKey = "\(newShortcutKey)_cleared"
            if defaults.object(forKey: newClearedKey) == nil,
               defaults.object(forKey: oldClearedKey) != nil {
                defaults.set(defaults.bool(forKey: oldClearedKey), forKey: newClearedKey)
            }
        }
    }
}

private enum LegacyModeDataKey {
    static let configurations = "powerModeConfigurationsV2"
    static let shortcutPrefix = "Shortcut_powerMode_"
}
