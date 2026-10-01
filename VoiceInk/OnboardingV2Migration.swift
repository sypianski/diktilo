import Foundation

enum OnboardingV2Migration {
    private static let legacyCompletedKey = "hasCompletedOnboarding"
    private static let completedKey = "hasCompletedOnboardingV2"
    private static let preparedKey = "hasPreparedOnboardingV2"
    private static let legacyOutputProfilesKey = "powerModeConfigurationsV2"
    private static let modeConfigurationsKey = "modeConfigurationsV2"
    private static let activeConfigurationIdKey = "activeConfigurationId"

    static func prepareIfNeeded(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyCompletedKey)

        guard !defaults.bool(forKey: completedKey),
              !defaults.bool(forKey: preparedKey) else {
            return
        }

        clearModeStorage(defaults: defaults)
        OnboardingStorageKeys.onboardingKeys.forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.set(true, forKey: preparedKey)
        // Before LegacyFinishShortcutMigration, so it sees the seeded "Copy".
        DefaultModeSeeder.seedIfEmpty()
    }

    private static func clearModeStorage(defaults: UserDefaults) {
        let modeIds = modeConfigurationIds(forKey: modeConfigurationsKey, defaults: defaults)
            .union(modeConfigurationIds(forKey: legacyOutputProfilesKey, defaults: defaults))
            .union(StarterModeCatalog.ids)

        for id in modeIds {
            ShortcutStore.removeShortcutStorage(for: .profile(id))
            removeLegacyPowerModeShortcutStorage(for: id, defaults: defaults)
        }

        defaults.removeObject(forKey: modeConfigurationsKey)
        defaults.removeObject(forKey: legacyOutputProfilesKey)
        defaults.removeObject(forKey: activeConfigurationIdKey)
    }

    private static func modeConfigurationIds(forKey key: String, defaults: UserDefaults) -> Set<UUID> {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        if let configs = try? JSONDecoder().decode([OutputProfile].self, from: data) {
            return Set(configs.map(\.id))
        }

        guard
            let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        return Set(objects.compactMap { object in
            (object["id"] as? String).flatMap(UUID.init(uuidString:))
        })
    }

    private static func removeLegacyPowerModeShortcutStorage(for id: UUID, defaults: UserDefaults) {
        let key = "Shortcut_powerMode_\(id.uuidString)"
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: "\(key)_cleared")
    }
}
