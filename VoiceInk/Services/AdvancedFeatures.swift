import Foundation

/// Hidden-by-default advanced features. This is the single place that knows
/// which features have a visibility flag, where it is stored, and how to tell
/// that a user already runs a non-default configuration of the feature.
///
/// A flag only controls whether the feature's UI is revealed / the feature is
/// active; the feature's own settings are never touched when it is switched off.
enum AdvancedFeature: String, CaseIterable {
    case modes
    case advancedOutputs
    case saveTargets
    case aiEnhancement
    case fileTranscription

    static let defaultValue = false

    var defaultsKey: String { "AdvancedFeature.\(rawValue)" }

    func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) == nil
            ? Self.defaultValue
            : defaults.bool(forKey: defaultsKey)
    }

    func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }

    /// True when the user has stored an explicit choice (on or off).
    func hasExplicitValue(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) != nil
    }
}

enum AdvancedFeatures {
    /// Returns true when the stored configuration of a feature differs from
    /// its defaults (so hiding the feature would hide something in use).
    typealias Detector = (UserDefaults) -> Bool

    static let migrationKey = "advancedFeaturesMigrationV1"

    /// Per-feature detectors. Each feature's task replaces its `false` stub
    /// with the real rule.
    static let defaultDetectors: [AdvancedFeature: Detector] = [
        .modes: { AdvancedFeatures.modesInUse(in: $0) },
        .advancedOutputs: { _ in false },
        .saveTargets: { _ in false },
        .aiEnhancement: { _ in false },
        .fileTranscription: { _ in false }
    ]

    /// True when the stored modes go beyond the single untouched "Paste" mode a
    /// fresh install starts with: several modes (the old default pair was
    /// Paste + Copy), or one mode that was changed (other output, AI, a trigger,
    /// auto-send or its own shortcut). Reads the stored JSON directly, so it
    /// works with an injected defaults suite and without the manager singleton.
    static func modesInUse(in defaults: UserDefaults) -> Bool {
        guard let data = defaults.data(forKey: OutputProfileManager.configKey)
                ?? defaults.data(forKey: LegacyModeDataKey.configurations),
              let modes = try? JSONDecoder().decode([OutputProfile].self, from: data),
              !modes.isEmpty else {
            return false
        }
        guard modes.count == 1, let mode = modes.first else { return true }

        let hasShortcut = defaults.data(
            forKey: ShortcutAction.profile(mode.id).userDefaultsKey
        ) != nil
        let hasTriggers = !(mode.appConfigs ?? []).isEmpty
            || !(mode.urlConfigs ?? []).isEmpty
            || !(mode.triggerGroups ?? []).isEmpty
            || !mode.triggerWords.isEmpty
        return mode.outputMode != .paste
            || mode.isAIEnhancementEnabled
            || mode.autoSendKey != .none
            || hasTriggers
            || hasShortcut
    }

    /// One-shot: switches a feature on when a detector reports a non-default
    /// configuration. Never overwrites a value the user has set explicitly.
    static func runMigrationIfNeeded(
        defaults: UserDefaults = .standard,
        detectors: [AdvancedFeature: Detector] = defaultDetectors
    ) {
        guard !defaults.bool(forKey: migrationKey) else { return }

        for feature in AdvancedFeature.allCases {
            guard !feature.hasExplicitValue(in: defaults),
                  detectors[feature]?(defaults) == true else { continue }
            feature.setEnabled(true, in: defaults)
        }

        defaults.set(true, forKey: migrationKey)
    }
}
