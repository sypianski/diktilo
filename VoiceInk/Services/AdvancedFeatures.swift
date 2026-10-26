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
        .advancedOutputs: { AdvancedFeatures.advancedOutputsInUse(in: $0) },
        .saveTargets: { AdvancedFeatures.saveTargetsInUse(in: $0) },
        .aiEnhancement: { _ in false },
        .fileTranscription: { AdvancedFeatures.fileTranscriptionInUse(in: $0) }
    ]

    /// Mode picked on the file screen (set once the user chooses one there).
    static let fileTranscriptionModeKey = "fileTranscriptionModeID"
    /// Set when a file transcription actually starts.
    static let fileTranscriptionUsedKey = "fileTranscriptionUsed"

    /// True when there is a trace of the file screen being used: a transcription
    /// was started, or a mode was picked there. History (SwiftData) is not read
    /// here, so files transcribed by builds that did not set the flag are not
    /// detected; the toggle in Settings -> Advanced covers that case.
    static func fileTranscriptionInUse(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: fileTranscriptionUsedKey)
            || defaults.string(forKey: fileTranscriptionModeKey) != nil
    }

    /// Records that a file transcription was started, so a later migration or
    /// check can tell the feature is in use.
    static func markFileTranscriptionUsed(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: fileTranscriptionUsedKey)
    }

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

    /// True when at least one save target is stored (entries of a removed
    /// strategy are dropped on load, so they do not count) or a stored mode
    /// delivers to a target. Reads the JSON directly, like `modesInUse`.
    static func saveTargetsInUse(in defaults: UserDefaults) -> Bool {
        if let data = defaults.data(forKey: SaveTargetManager.defaultsKey),
           let stored = try? JSONDecoder().decode([LossyTarget].self, from: data),
           stored.contains(where: { $0.target != nil }) {
            return true
        }
        guard let data = defaults.data(forKey: OutputProfileManager.configKey)
                ?? defaults.data(forKey: LegacyModeDataKey.configurations),
              let modes = try? JSONDecoder().decode([OutputProfile].self, from: data) else {
            return false
        }
        return modes.contains { $0.outputMode == .saveTarget }
    }

    /// True when a stored mode ends in a shell command or a save target (the
    /// outputs hidden behind "Advanced outputs"). Reads the JSON directly.
    static func advancedOutputsInUse(in defaults: UserDefaults) -> Bool {
        guard let data = defaults.data(forKey: OutputProfileManager.configKey)
                ?? defaults.data(forKey: LegacyModeDataKey.configurations),
              let modes = try? JSONDecoder().decode([OutputProfile].self, from: data) else {
            return false
        }
        return modes.contains { $0.outputMode == .customCommand || $0.outputMode == .saveTarget }
    }

    /// True when at least one stored mode has AI enhancement switched on. Used to
    /// keep the AI settings open for people who already rely on them. Reads the
    /// JSON directly, like the detectors above.
    static func anyModeUsesAI(in defaults: UserDefaults) -> Bool {
        guard let data = defaults.data(forKey: OutputProfileManager.configKey)
                ?? defaults.data(forKey: LegacyModeDataKey.configurations),
              let modes = try? JSONDecoder().decode([OutputProfile].self, from: data) else {
            return false
        }
        return modes.contains { $0.isAIEnhancementEnabled }
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
