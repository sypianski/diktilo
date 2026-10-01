import Foundation

/// The languages the user dictates in, most used first. An empty list means
/// "detect the language".
///
/// What a model receives (`effectiveLanguage(for:)`):
/// - one language: that language, as before (mapped to the model's own code,
///   e.g. "pl" → "pl-PL" for Apple Speech);
/// - several: "auto" for models that detect the language themselves, else the
///   first language of the list the model supports.
/// Cloud SDK calls (LLMkit) take a single language, so a list of hints can't
/// be passed on; auto-detection is the one way to cover several languages.
///
/// "SelectedLanguage" stays as a mirror of what the current model receives:
/// the Whisper prompt, Apple Speech assets and system info still read it.
enum DictationLanguages {
    static let userDefaultsKey = "DictationLanguages"

    /// Languages Deepgram Nova-3 code-switches between with `language=multi`.
    static let deepgramMultiLanguages: Set<String> = ["en", "es", "fr", "de", "hi", "ru", "pt", "ja", "it", "nl"]

    static var codes: [String] {
        get {
            if let stored = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
                return stored
            }
            return migrateFromSelectedLanguage()
        }
        set {
            var seen = Set<String>()
            let cleaned = newValue
                .filter { !$0.isEmpty && $0 != "auto" }
                .filter { seen.insert(baseCode($0)).inserted }
            UserDefaults.standard.set(cleaned, forKey: userDefaultsKey)
            NotificationCenter.default.post(name: .dictationLanguagesDidChange, object: nil)
        }
    }

    /// A single legacy value: "auto" clears the list, anything else becomes it.
    static func setFromLegacy(_ language: String) {
        codes = (language == "auto" || language.isEmpty) ? [] : [language]
    }

    // MARK: - Per model

    static func effectiveLanguage(for model: any TranscriptionModel) -> String {
        let supported = TranscriptionLanguageSupport.languages(for: model)
        let languages = codes

        if languages.count == 1, let match = code(for: languages[0], in: supported) {
            return match
        }
        // Deepgram treats a missing language as English, so "auto" would
        // force English; Nova-3 code-switches with "multi" across ten languages
        // (developers.deepgram.com/docs/models-languages-overview).
        if languages.count > 1, model.provider == .deepgram {
            if model.name == "nova-3", languages.allSatisfy({ deepgramMultiLanguages.contains(baseCode($0)) }) {
                return "multi"
            }
        } else if languages.count != 1, supported["auto"] != nil {
            return "auto"
        }
        for language in languages {
            if let match = code(for: language, in: supported) {
                return match
            }
        }
        return TranscriptionLanguageSupport.validLanguageOrFallback(nil, for: model)
    }

    /// The model's code for a language: the exact key, the bare language, or a
    /// regional variant (the user's region first, then "pl-PL"-style).
    static func code(for language: String, in supported: [String: String]) -> String? {
        if supported[language] != nil { return language }
        let base = baseCode(language)
        if supported[base] != nil { return base }

        let variants = supported.keys.filter { baseCode($0) == base }
        guard !variants.isEmpty else { return nil }
        if let region = Locale.current.region?.identifier,
           let variant = variants.first(where: { $0.hasSuffix("-\(region)") }) {
            return variant
        }
        if let variant = variants.first(where: { $0.lowercased() == "\(base)-\(base)" }) {
            return variant
        }
        return variants.sorted().first
    }

    /// Languages of the list the model can't take at all ("Polish" for an
    /// English-only model). Empty when it handles them, or detects any.
    static func unsupportedLanguages(by model: any TranscriptionModel) -> [String] {
        let supported = TranscriptionLanguageSupport.languages(for: model)
        return codes.filter { code(for: $0, in: supported) == nil }
    }

    /// Keeps "SelectedLanguage" equal to what `model` receives.
    static func syncLegacySelectedLanguage(for model: (any TranscriptionModel)?) {
        let value = model.map(effectiveLanguage(for:)) ?? (codes.count == 1 ? codes[0] : "auto")
        guard UserDefaults.standard.string(forKey: GlobalTranscriptionSettings.Keys.language) != value else { return }
        UserDefaults.standard.set(value, forKey: GlobalTranscriptionSettings.Keys.language)
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    // MARK: - Choosing

    /// Every language some model transcribes, as bare codes, by name in the UI language.
    static var selectableLanguages: [(code: String, name: String)] {
        let bases = Set(LanguageDictionary.all.keys.map(baseCode)).subtracting(["auto", ""])
        return bases
            .map { (code: $0, name: displayName(for: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func displayName(for code: String) -> String {
        let name = ModelAdvisor.languageName(baseCode(code))
        return name == baseCode(code) ? (LanguageDictionary.all[code] ?? code) : name
    }

    static func baseCode(_ identifier: String) -> String {
        ModelAdvisor.baseCode(identifier)
    }

    // MARK: - Migration

    /// Before the list existed there was one "SelectedLanguage", possibly
    /// "auto". A stored value is kept as it was; the registered default ("en")
    /// was never a choice, so without one the list starts empty (detect).
    /// Stored right away, also when empty: "SelectedLanguage" becomes a mirror
    /// afterwards and must never be read back as a choice.
    private static func migrateFromSelectedLanguage() -> [String] {
        let legacy = ModelAdvisor.explicitSelectedLanguage ?? "auto"
        let migrated = (legacy == "auto" || legacy.isEmpty) ? [] : [legacy]
        UserDefaults.standard.set(migrated, forKey: userDefaultsKey)
        return migrated
    }
}

extension Notification.Name {
    static let dictationLanguagesDidChange = Notification.Name("dictationLanguagesDidChange")
}
