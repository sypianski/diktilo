import Foundation
import Darwin

/// What this Mac brings to local transcription.
struct MacHardwareProfile: Equatable {
    var chipName: String
    var isAppleSilicon: Bool
    var memoryGB: Int
    var macOSMajor: Int
    var macOSVersion: String
    var freeDiskGB: Int?

    /// The chip and memory don't change while the app runs; read them once
    /// for views that ask on every render.
    static let cached = current()

    static func current() -> MacHardwareProfile {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "\(os.majorVersion).\(os.minorVersion)"

        return MacHardwareProfile(
            chipName: sysctlString("machdep.cpu.brand_string") ?? SystemArchitecture.current,
            isAppleSilicon: isArm64Hardware(),
            memoryGB: Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()),
            macOSMajor: os.majorVersion,
            macOSVersion: version,
            freeDiskGB: freeDiskGB()
        )
    }

    /// The hardware, not the build: true on Apple Silicon even under Rosetta.
    private static func isArm64Hardware() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        return SystemArchitecture.isAppleSilicon
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func freeDiskGB() -> Int? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Int(bytes / 1_073_741_824)
    }
}

struct ModelRecommendation: Equatable {
    /// `TranscriptionModelRegistry` name of the suggested model.
    let modelName: String
    let reason: String
    let alternativeModelName: String?
    let alternativeReason: String?
    /// Local models will be slow here; a cloud model with an API key fits better.
    let suggestsCloud: Bool
}

/// Picks a transcription model for this Mac and the language the user
/// dictates in. The rules are a pure function of the hardware profile and the
/// language, so they can be tested without a Mac of every kind.
enum ModelAdvisor {
    /// Languages Parakeet V3 transcribes (LanguageDictionary, `.fluidAudio`).
    static let parakeetLanguages: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
        "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro",
        "ru", "sk", "sl", "sv", "uk"
    ]

    /// Languages of Apple Speech (LanguageDictionary.appleNative), macOS 26+.
    static let appleSpeechLanguages: Set<String> = ["de", "en", "es", "fr", "it", "ja", "ko", "pt", "zh"]

    /// Under this much memory a large Whisper model crowds out everything else.
    static let comfortableMemoryGB = 8

    static func recommend(for hardware: MacHardwareProfile, language: String) -> ModelRecommendation {
        recommend(for: hardware, languages: [language])
    }

    /// With several languages a model has to cover all of them: Parakeet V3
    /// only when every one is a Parakeet language, the English models only
    /// for English alone.
    static func recommend(for hardware: MacHardwareProfile, languages: [String]) -> ModelRecommendation {
        var seen = Set<String>()
        let bases = languages.map(baseCode).filter { !$0.isEmpty && seen.insert($0).inserted }
        let isEnglishOnly = bases == ["en"] || bases.isEmpty
        let allIn: (Set<String>) -> Bool = { set in !bases.isEmpty && bases.allSatisfy(set.contains) }

        let isSeveral = bases.count > 1
        // Apple Speech doesn't detect the language, so it only fits one.
        let appleSpeech: (name: String, reason: String)? =
            hardware.isAppleSilicon && hardware.macOSMajor >= 26 && !isSeveral && allIn(appleSpeechLanguages)
            ? ("apple-speech", String(localized: "Apple Speech is built into macOS, so there is nothing to download."))
            : nil

        // Local models don't run reliably on Intel Macs: keep it small and
        // point to the cloud.
        guard hardware.isAppleSilicon else {
            let isSmallMemory = hardware.memoryGB < comfortableMemoryGB
            let modelName: String
            switch (isEnglishOnly, isSmallMemory) {
            case (true, true): modelName = "ggml-tiny.en"
            case (true, false): modelName = "ggml-base.en"
            case (false, true): modelName = "ggml-tiny"
            case (false, false): modelName = "ggml-base"
            }
            return ModelRecommendation(
                modelName: modelName,
                reason: String(localized: "Local models are slow on Intel Macs, so a small one is the safe choice. A cloud model with an API key will be faster and more accurate."),
                alternativeModelName: nil,
                alternativeReason: nil,
                suggestsCloud: true
            )
        }

        if isEnglishOnly {
            return ModelRecommendation(
                modelName: "parakeet-tdt-0.6b-v2",
                reason: String(localized: "Made for English: fast, accurate and the smallest download."),
                alternativeModelName: "parakeet-tdt-0.6b-v3",
                alternativeReason: String(localized: "Parakeet V3, if you also dictate in other European languages."),
                suggestsCloud: false
            )
        }

        if allIn(parakeetLanguages) {
            return ModelRecommendation(
                modelName: "parakeet-tdt-0.6b-v3",
                reason: isSeveral
                    ? String(localized: "Fast and accurate in all your languages and recognizes which one you speak; light on memory, and it can transcribe live.")
                    : String(localized: "Fast and accurate in your language, light on memory, and it can transcribe live."),
                alternativeModelName: appleSpeech?.name,
                alternativeReason: appleSpeech?.reason,
                suggestsCloud: false
            )
        }

        if hardware.memoryGB >= comfortableMemoryGB {
            return ModelRecommendation(
                modelName: "ggml-large-v3-turbo-q5_0",
                reason: isSeveral
                    ? String(localized: "Parakeet doesn't cover all your languages. Whisper Large v3 Turbo does and recognizes which one you speak, with high accuracy at a moderate size.")
                    : String(localized: "Parakeet doesn't cover your language. Whisper Large v3 Turbo does, with high accuracy at a moderate size."),
                alternativeModelName: appleSpeech?.name,
                alternativeReason: appleSpeech?.reason,
                suggestsCloud: false
            )
        }

        return ModelRecommendation(
            modelName: "ggml-base",
            reason: isSeveral
                ? String(localized: "Parakeet doesn't cover all your languages, and this Mac has little memory for a large model. Whisper Base handles them at a small size.")
                : String(localized: "Parakeet doesn't cover your language, and this Mac has little memory for a large model. Whisper Base handles it at a small size."),
            alternativeModelName: appleSpeech?.name,
            alternativeReason: appleSpeech?.reason,
            suggestsCloud: false
        )
    }

    // MARK: - Dictation language

    /// The explicit setting, else the first system language any model can
    /// transcribe, else English.
    static func dictationLanguage(selected: String?, preferredLanguages: [String]) -> String {
        if let selected, !selected.isEmpty, selected != "auto" {
            return baseCode(selected)
        }

        let known = Set(LanguageDictionary.all.keys)
        for identifier in preferredLanguages {
            let code = baseCode(identifier)
            if known.contains(code) {
                return code
            }
        }
        return "en"
    }

    /// "SelectedLanguage" is registered with "en" as its default, so only a
    /// value actually stored by the user counts as their choice.
    static var explicitSelectedLanguage: String? {
        guard let domain = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: domain)?[GlobalTranscriptionSettings.Keys.language] as? String
    }

    /// The chosen dictation languages; with none chosen (detect), the first
    /// system language any model can transcribe, as a best guess.
    static func currentDictationLanguages() -> [String] {
        let chosen = DictationLanguages.codes.map(baseCode)
        if !chosen.isEmpty { return chosen }
        return [dictationLanguage(selected: nil, preferredLanguages: Locale.preferredLanguages)]
    }

    static func currentRecommendation() -> ModelRecommendation {
        recommend(for: .cached, languages: currentDictationLanguages())
    }

    static func baseCode(_ identifier: String) -> String {
        String(identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }

    // MARK: - Display

    /// Language name in the app's UI language ("polski"), not the system's.
    static func languageName(_ code: String) -> String {
        let uiLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return uiLocale.localizedString(forLanguageCode: code) ?? code
    }

    static func hardwareSummary(_ hardware: MacHardwareProfile) -> String {
        String(
            format: String(localized: "%@ · %lld GB RAM · macOS %@"),
            hardware.chipName,
            Int64(hardware.memoryGB),
            hardware.macOSVersion
        )
    }

    static func displayName(forModelNamed name: String) -> String {
        TranscriptionModelRegistry.models.first { $0.name == name }?.displayName ?? name
    }
}
