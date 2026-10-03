import Testing
@testable import Diktilo

struct ModelAdvisorTests {
    private func mac(
        appleSilicon: Bool = true,
        memoryGB: Int = 16,
        macOS: Int = 15
    ) -> MacHardwareProfile {
        MacHardwareProfile(
            chipName: appleSilicon ? "Apple M2" : "Intel(R) Core(TM) i5",
            isAppleSilicon: appleSilicon,
            memoryGB: memoryGB,
            macOSMajor: macOS,
            macOSVersion: "\(macOS).0",
            freeDiskGB: 100
        )
    }

    @Test func europeanLanguageOnAppleSiliconGetsParakeetV3() {
        let recommendation = ModelAdvisor.recommend(for: mac(), language: "pl")
        #expect(recommendation.modelName == "parakeet-tdt-0.6b-v3")
        #expect(!recommendation.suggestsCloud)
    }

    @Test func englishGetsParakeetV2WithV3AsAlternative() {
        let recommendation = ModelAdvisor.recommend(for: mac(), language: "en-US")
        #expect(recommendation.modelName == "parakeet-tdt-0.6b-v2")
        #expect(recommendation.alternativeModelName == "parakeet-tdt-0.6b-v3")
    }

    @Test func languageOutsideParakeetGetsWhisperTurbo() {
        let recommendation = ModelAdvisor.recommend(for: mac(), language: "ar")
        #expect(recommendation.modelName == "ggml-large-v3-turbo-q5_0")
    }

    @Test func languageOutsideParakeetWithLittleMemoryGetsWhisperBase() {
        let recommendation = ModelAdvisor.recommend(for: mac(memoryGB: 4), language: "ar")
        #expect(recommendation.modelName == "ggml-base")
    }

    @Test func appleSpeechIsOfferedOnMacOS26ForItsLanguages() {
        let recommendation = ModelAdvisor.recommend(for: mac(macOS: 26), language: "ja")
        #expect(recommendation.modelName == "ggml-large-v3-turbo-q5_0")
        #expect(recommendation.alternativeModelName == "apple-speech")

        let older = ModelAdvisor.recommend(for: mac(macOS: 15), language: "ja")
        #expect(older.alternativeModelName == nil)
    }

    @Test func intelMacGetsSmallWhisperAndCloudHint() {
        let polish = ModelAdvisor.recommend(for: mac(appleSilicon: false), language: "pl")
        #expect(polish.modelName == "ggml-base")
        #expect(polish.suggestsCloud)

        let englishLowMemory = ModelAdvisor.recommend(for: mac(appleSilicon: false, memoryGB: 4), language: "en")
        #expect(englishLowMemory.modelName == "ggml-tiny.en")
    }

    @Test func explicitLanguageWins() {
        #expect(ModelAdvisor.dictationLanguage(selected: "de", preferredLanguages: ["pl-PL"]) == "de")
    }

    @Test func autoFallsBackToFirstTranscribableSystemLanguage() {
        // Ido and Esperanto aren't transcription languages; Polish is.
        let language = ModelAdvisor.dictationLanguage(selected: "auto", preferredLanguages: ["io-PL", "eo-PL", "pl-PL"])
        #expect(language == "pl")
    }

    @Test func nothingKnownFallsBackToEnglish() {
        #expect(ModelAdvisor.dictationLanguage(selected: nil, preferredLanguages: ["io"]) == "en")
    }

    @Test func recommendedModelsExistInRegistry() {
        let names = Set(TranscriptionModelRegistry.models.map(\.name))
        for hardware in [mac(), mac(memoryGB: 4), mac(appleSilicon: false), mac(appleSilicon: false, memoryGB: 4), mac(macOS: 26)] {
            for language in ["en", "pl", "ar", "ja"] {
                let recommendation = ModelAdvisor.recommend(for: hardware, language: language)
                #expect(names.contains(recommendation.modelName))
                if let alternative = recommendation.alternativeModelName {
                    #expect(names.contains(alternative))
                }
            }
        }
    }
}
