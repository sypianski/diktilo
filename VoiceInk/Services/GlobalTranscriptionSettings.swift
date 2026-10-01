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
    }

    static let defaultLanguage = "pl"

    /// Persisted name of the selected transcription model, or nil to fall back to
    /// the first usable model.
    static var modelName: String? {
        get { UserDefaults.standard.string(forKey: Keys.model) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.model) }
    }

    /// What the current model receives; the languages themselves are
    /// `DictationLanguages`. Setting it replaces that list with this one
    /// language ("auto" clears it), for the callers that still set one.
    static var language: String {
        get { UserDefaults.standard.string(forKey: Keys.language) ?? defaultLanguage }
        set {
            DictationLanguages.setFromLegacy(newValue)
            UserDefaults.standard.set(newValue, forKey: Keys.language)
        }
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
}
