import Foundation

struct WorekEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
}

@MainActor
final class WorekStore: ObservableObject {
    static let shared = WorekStore()

    @Published private(set) var entries: [WorekEntry] = []

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("worek.json")
    }

    private init() {
        load()
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(WorekEntry(text: trimmed), at: 0)
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let decoded = try? JSONDecoder().decode([WorekEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        let url = Self.storageURL
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
