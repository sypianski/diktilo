import Foundation

// MARK: - SaveTargetFileFormat

enum SaveTargetFileFormat: String, Codable, CaseIterable {
    case markdown
    case plainText

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }

    var displayName: String {
        switch self {
        case .markdown: return String(localized: "Markdown (.md)")
        case .plainText: return String(localized: "Plain Text (.txt)")
        }
    }
}

// MARK: - SaveTargetConfig

struct SaveTargetConfig: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var icon: String     // SF Symbol name
    var strategy: Strategy

    enum Strategy: Codable, Equatable {
        case file(FileStrategy)
        case urlScheme(template: String, activates: Bool)
        case shellCommand(command: String)
        case sako

        // Manual Codable so associated values round-trip cleanly.
        private enum CodingKeys: String, CodingKey {
            case type, fileStrategy, urlTemplate, urlActivates, shellCommand
        }
        private enum TypeTag: String, Codable {
            case file, urlScheme, shellCommand, sako
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let tag = try container.decode(TypeTag.self, forKey: .type)
            switch tag {
            case .file:
                let fs = try container.decode(FileStrategy.self, forKey: .fileStrategy)
                self = .file(fs)
            case .urlScheme:
                let template = try container.decode(String.self, forKey: .urlTemplate)
                // Back-compat: existing saved targets without `urlActivates` default to true
                // (previously activating was always the behavior).
                let activates = try container.decodeIfPresent(Bool.self, forKey: .urlActivates) ?? true
                self = .urlScheme(template: template, activates: activates)
            case .shellCommand:
                let cmd = try container.decode(String.self, forKey: .shellCommand)
                self = .shellCommand(command: cmd)
            case .sako:
                self = .sako
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .file(let fs):
                try container.encode(TypeTag.file, forKey: .type)
                try container.encode(fs, forKey: .fileStrategy)
            case .urlScheme(let template, let activates):
                try container.encode(TypeTag.urlScheme, forKey: .type)
                try container.encode(template, forKey: .urlTemplate)
                try container.encode(activates, forKey: .urlActivates)
            case .shellCommand(let cmd):
                try container.encode(TypeTag.shellCommand, forKey: .type)
                try container.encode(cmd, forKey: .shellCommand)
            case .sako:
                try container.encode(TypeTag.sako, forKey: .type)
            }
        }
    }

    struct FileStrategy: Codable, Equatable {
        var directoryPath: String        // may start with "~"
        var filenameTemplate: String     // tokens: {date} {time} {datetime} {slug}
        var format: SaveTargetFileFormat
        var appendToExisting: Bool

        init(
            directoryPath: String = "~/Documents",
            filenameTemplate: String = "{date}-{slug}",
            format: SaveTargetFileFormat = .markdown,
            appendToExisting: Bool = false
        ) {
            self.directoryPath = directoryPath
            self.filenameTemplate = filenameTemplate
            self.format = format
            self.appendToExisting = appendToExisting
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "square.and.arrow.down",
        strategy: Strategy
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.strategy = strategy
    }

    // MARK: - Display helpers

    var strategyDisplayName: String {
        switch strategy {
        case .file: return String(localized: "File")
        case .urlScheme: return String(localized: "URL Scheme")
        case .shellCommand: return String(localized: "Shell Command")
        case .sako: return String(localized: "Sako")
        }
    }

    /// Whether the target opens and activates the destination app on delivery.
    /// Only applies to `.urlScheme`; all other strategies return true by convention.
    var activatesOnDelivery: Bool {
        switch strategy {
        case .urlScheme(_, let activates): return activates
        default: return true
        }
    }

    // MARK: - Presets

    /// Notaro (cc.sypianski.notaro) ingests via notaro://add?text=…&source=…;
    /// the source parameter feeds its note classifier, so keep it stable.
    static func notaroPreset() -> SaveTargetConfig {
        SaveTargetConfig(
            id: UUID(),
            name: "Notaro",
            icon: "note.text",
            strategy: .urlScheme(template: "notaro://add?text={{text}}&source=diktilo", activates: false)
        )
    }
}

// MARK: - SaveTargetManager

final class SaveTargetManager: ObservableObject {
    static let shared = SaveTargetManager()

    @Published var targets: [SaveTargetConfig] = []

    private let defaultsKey = "saveTargetsV1"

    private init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SaveTargetConfig].self, from: data) else {
            return
        }
        targets = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: Mutations

    func add(_ target: SaveTargetConfig) {
        guard !targets.contains(where: { $0.id == target.id }) else { return }
        targets.append(target)
        save()
    }

    func update(_ target: SaveTargetConfig) {
        guard let index = targets.firstIndex(where: { $0.id == target.id }) else { return }
        targets[index] = target
        save()
    }

    func delete(with id: UUID) {
        targets.removeAll { $0.id == id }
        save()
    }

    func target(withID id: UUID) -> SaveTargetConfig? {
        targets.first { $0.id == id }
    }
}
