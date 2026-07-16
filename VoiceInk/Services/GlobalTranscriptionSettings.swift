import Foundation

/// Single source of truth for the app-wide transcription settings that used to
/// live per-mode (model, language, realtime streaming, paragraph formatting).
///
/// After the Modes → OutputProfile refactor these are global: one transcription
/// configuration is shared by every OutputProfile. Only AI enhancement, output
/// destination and triggers vary per profile.
enum GlobalTranscriptionSettings {
    enum Keys {
        static let model = "CurrentTranscriptionModel"
        static let language = "SelectedLanguage"
        static let isRealtimeEnabled = "IsRealtimeTranscriptionEnabled"
        static let isTextFormattingEnabled = "IsTextFormattingEnabled"
        static let isAIEnhancementEnabled = "IsAIEnhancementEnabled"
    }

    static let defaultLanguage = "pl"

    /// Persisted name of the selected transcription model, or nil to fall back to
    /// the first usable model.
    static var modelName: String? {
        get { UserDefaults.standard.string(forKey: Keys.model) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.model) }
    }

    static var language: String {
        get { UserDefaults.standard.string(forKey: Keys.language) ?? defaultLanguage }
        set { UserDefaults.standard.set(newValue, forKey: Keys.language) }
    }

    static var isRealtimeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.isRealtimeEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.isRealtimeEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isRealtimeEnabled) }
    }

    static var isTextFormattingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isTextFormattingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isTextFormattingEnabled) }
    }

    /// Global master switch for AI enhancement. When OFF, no mode enhances,
    /// regardless of the per-mode `isAIEnhancementEnabled` toggle. When ON,
    /// per-mode `isAIEnhancementEnabled` still gates individual modes.
    ///
    /// Defaults to ON so existing users' modes with enhancement configured keep
    /// working after upgrade.
    static var isAIEnhancementEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.isAIEnhancementEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.isAIEnhancementEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isAIEnhancementEnabled) }
    }
}
