import Foundation
import AppKit
import os

/// Sends dictated text to sako — either through the bundled/installed CLI, or
/// as a direct JSONL append fallback so Diktilo works even without sako installed.
/// The wire format is the SPEC in SPEC.md in the Sako repository.
@MainActor
final class SakoClient {
    static let shared = SakoClient()
    private let logger = Logger(subsystem: "cc.sypianski.diktilo", category: "SakoClient")

    private init() {}

    private static let bundleIdentifier = "cc.sypianski.sako"

    // MARK: - Send

    /// Persist `text` to sako. Returns true on success.
    @discardableResult
    func send(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let cli = findCLI(), sendViaCLI(cli, text: trimmed) {
            return true
        }
        return appendDirectly(text: trimmed)
    }

    /// Opens the Sako GUI app if installed, otherwise no-op.
    func openApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
            NSWorkspace.shared.open(url)
        } else {
            logger.warning("Sako.app not installed (bundle \(Self.bundleIdentifier)); openApp is a no-op.")
        }
    }

    // MARK: - CLI path

    private func findCLI() -> URL? {
        let candidates = [
            "/usr/local/bin/sako",
            "/opt/homebrew/bin/sako",
            (NSString("~/.local/bin/sako").expandingTildeInPath as String),
        ].map { URL(fileURLWithPath: $0) }

        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        // Bundled inside Sako.app.
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
            let inside = appURL.appendingPathComponent("Contents/MacOS/sako")
            if FileManager.default.isExecutableFile(atPath: inside.path) {
                return inside
            }
        }
        return nil
    }

    private func sendViaCLI(_ cli: URL, text: String) -> Bool {
        let process = Process()
        process.executableURL = cli
        process.arguments = ["add", "-", "--source", "diktilo"]

        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            logger.error("sako CLI launch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        if let data = text.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        process.waitUntilExit()
        if process.terminationStatus != 0 {
            logger.warning("sako CLI exited with status \(process.terminationStatus)")
            return false
        }
        return true
    }

    // MARK: - Direct JSONL fallback

    private var entriesURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sako")
            .appendingPathComponent("entries.jsonl")
    }

    private func appendDirectly(text: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: entriesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var line = try encoder.encode([
                "id": AnyEncodable(SakoClient.generateULID()),
                "text": AnyEncodable(text),
                "createdAt": AnyEncodable(Date()),
                "source": AnyEncodable("diktilo"),
            ])
            line.append(0x0A)

            let fd = open(entriesURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard fd >= 0 else {
                logger.error("sako fallback open failed: \(String(cString: strerror(errno)), privacy: .public)")
                return false
            }
            defer { close(fd) }

            let written = line.withUnsafeBytes { buf -> Int in
                guard let base = buf.baseAddress else { return -1 }
                return write(fd, base, buf.count)
            }
            return written == line.count
        } catch {
            logger.error("sako fallback failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static func generateULID(at date: Date = Date()) -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let ms = UInt64(date.timeIntervalSince1970 * 1000)
        var timePart = ""
        var remaining = ms
        for _ in 0..<10 {
            timePart = String(alphabet[Int(remaining & 0x1F)]) + timePart
            remaining >>= 5
        }
        var randomPart = ""
        for _ in 0..<16 {
            randomPart.append(alphabet[Int(UInt8.random(in: 0...31))])
        }
        return timePart + randomPart
    }
}

/// Tiny type-erased Encodable so the fallback path can build a dictionary literal
/// without depending on SakoCore (Diktilo doesn't link the sako package).
private struct AnyEncodable: Encodable {
    private let write: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) {
        self.write = { encoder in try wrapped.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws { try write(encoder) }
}
