import Foundation

/// The order in which Diktilo tries models when one fails.
///
/// - Transcription: model names, app-wide. The first entry is the main model and
///   always mirrors `CurrentTranscriptionModel`; the rest are tried in order when
///   it fails.
/// - Enhancement: provider + model pairs tried *after* the model set in the mode,
///   which always comes first and is not part of this list.
///
/// Unavailable entries (no API key, model not downloaded) stay in the list so the
/// user sees why they are skipped; the runtime simply passes over them.
enum ModelFallbackChain {
    struct EnhancementLink: Codable, Hashable, Identifiable {
        let provider: String
        let model: String?

        var id: String { provider + "|" + (model ?? "") }
        var aiProvider: AIProvider? { AIProvider(rawValue: provider) }
    }

    enum Keys {
        static let transcription = "TranscriptionModelChain"
        static let enhancement = "EnhancementFallbackChain"
    }

    static let didChange = Notification.Name("ModelFallbackChainDidChange")

    // MARK: - Transcription

    /// Stored order with the current main model guaranteed first. Anything that
    /// sets `CurrentTranscriptionModel` directly (onboarding, backups) is folded
    /// in here, which also migrates installs that predate the chain.
    static var transcriptionOrder: [String] {
        var order = UserDefaults.standard.stringArray(forKey: Keys.transcription) ?? []
        if let main = GlobalTranscriptionSettings.modelName, !main.isEmpty {
            order.removeAll { $0 == main }
            order.insert(main, at: 0)
        }
        return deduplicated(order)
    }

    /// Saves a new order. The caller makes the first entry the main model
    /// (`TranscriptionModelManager.setDefaultTranscriptionModel`).
    static func setTranscriptionOrder(_ order: [String]) {
        UserDefaults.standard.set(deduplicated(order), forKey: Keys.transcription)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Moves a model to the front; called whenever the main model changes.
    static func promoteTranscription(_ name: String) {
        var order = UserDefaults.standard.stringArray(forKey: Keys.transcription) ?? []
        order.removeAll { $0 == name }
        order.insert(name, at: 0)
        setTranscriptionOrder(order)
    }

    static func removeTranscription(_ name: String) {
        var order = UserDefaults.standard.stringArray(forKey: Keys.transcription) ?? []
        guard order.contains(name) else { return }
        order.removeAll { $0 == name }
        setTranscriptionOrder(order)
    }

    // MARK: - Enhancement

    static var enhancementLinks: [EnhancementLink] {
        guard let data = UserDefaults.standard.data(forKey: Keys.enhancement),
              let links = try? JSONDecoder().decode([EnhancementLink].self, from: data) else {
            return []
        }
        return links
    }

    static func setEnhancementLinks(_ links: [EnhancementLink]) {
        var seen = Set<String>()
        let unique = links.filter { seen.insert($0.id).inserted }
        if let data = try? JSONEncoder().encode(unique) {
            UserDefaults.standard.set(data, forKey: Keys.enhancement)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - Helpers

    private static func deduplicated(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Every model of a fallback chain failed. With a single attempt the original
/// error is rethrown instead, so messages stay as they were without a chain.
struct ModelChainError: LocalizedError {
    struct Attempt {
        let name: String
        let reason: String
    }

    let attempts: [Attempt]

    var errorDescription: String? {
        let list = attempts.map { "\($0.name): \($0.reason)" }.joined(separator: "; ")
        return String(format: String(localized: "All models failed (%@)"), list)
    }

    static func reason(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
