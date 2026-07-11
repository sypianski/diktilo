import AppKit
import Foundation
import os

// MARK: - Errors

enum SaveTargetDeliveryError: Error, LocalizedError {
    case noText
    case targetNotConfigured
    case directoryCreationFailed(String)
    case fileWriteFailed(String)
    case invalidURLScheme(String)
    case urlOpenFailed(String)
    case shellCommandFailed(String)
    case sakoFailed

    var errorDescription: String? {
        switch self {
        case .noText:
            return String(localized: "No transcription text was available.")
        case .targetNotConfigured:
            return String(localized: "Save target is not configured.")
        case .directoryCreationFailed(let path):
            return String(format: String(localized: "Could not create directory: %@"), path)
        case .fileWriteFailed(let msg):
            return String(format: String(localized: "Failed to write file: %@"), msg)
        case .invalidURLScheme(let template):
            return String(format: String(localized: "Invalid URL scheme template: %@"), template)
        case .urlOpenFailed(let url):
            return String(format: String(localized: "Could not open URL: %@"), url)
        case .shellCommandFailed(let msg):
            return String(format: String(localized: "Shell command failed: %@"), msg)
        case .sakoFailed:
            return String(localized: "Failed to send text to Sako.")
        }
    }
}

// MARK: - Service

enum SaveTargetDeliveryService {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "SaveTargetDeliveryService"
    )

    /// Deliver `text` to `target`. Returns a human-readable success description.
    /// Must be called from `@MainActor` context (for sako strategy).
    @MainActor
    static func deliver(text: String, target: SaveTargetConfig) async throws -> String {
        switch target.strategy {
        case .file(let fileStrategy):
            // Offload file I/O off the main thread.
            return try await Task.detached(priority: .userInitiated) {
                try deliverFile(text: text, strategy: fileStrategy)
            }.value
        case .urlScheme(let template, let activates):
            return try await deliverURLScheme(text: text, template: template, activates: activates)
        case .shellCommand(let command):
            return try await deliverShellCommand(text: text, command: command)
        case .sako:
            return try deliverSako(text: text)
        }
    }

    // MARK: - File strategy

    private static func deliverFile(text: String, strategy: SaveTargetConfig.FileStrategy) throws -> String {
        let expandedDir = (strategy.directoryPath as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: expandedDir, isDirectory: true)

        // Create directory if needed.
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            throw SaveTargetDeliveryError.directoryCreationFailed(expandedDir)
        }

        let baseName = expandedFilename(template: strategy.filenameTemplate, text: text)
        let ext = strategy.format.fileExtension
        let fileURL = resolvedFileURL(directory: dirURL, baseName: baseName, ext: ext, append: strategy.appendToExisting)

        let separator: String
        switch strategy.format {
        case .markdown: separator = "\n\n---\n\n"
        case .plainText: separator = "\n\n"
        }

        do {
            if strategy.appendToExisting, FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                let appendData = (separator + text).data(using: .utf8) ?? Data()
                handle.write(appendData)
                try handle.close()
            } else {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            throw SaveTargetDeliveryError.fileWriteFailed(error.localizedDescription)
        }

        logger.notice("Saved transcript to \(fileURL.path, privacy: .public)")
        return fileURL.path
    }

    // MARK: - URL scheme strategy

    private static func deliverURLScheme(text: String, template: String, activates: Bool) async throws -> String {
        let allowedCharacters = CharacterSet.alphanumerics
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? text

        // Replace both {{text}} and {text} placeholders.
        let urlString = template
            .replacingOccurrences(of: "{{text}}", with: encoded)
            .replacingOccurrences(of: "{text}", with: encoded)

        guard let url = URL(string: urlString) else {
            throw SaveTargetDeliveryError.invalidURLScheme(template)
        }

        if activates {
            // Classic path: open URL and bring the target app to front.
            guard NSWorkspace.shared.open(url) else {
                throw SaveTargetDeliveryError.urlOpenFailed(urlString)
            }
        } else {
            // Silent path: deliver in the background without activating the target app.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.open(url, configuration: config) { _, error in
                    if let error {
                        continuation.resume(throwing: SaveTargetDeliveryError.urlOpenFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        logger.notice("Opened URL scheme (activates=\(activates, privacy: .public)): \(url.scheme ?? "?", privacy: .public)://…")
        return urlString
    }

    // MARK: - Shell command strategy

    private static func deliverShellCommand(text: String, command: String) async throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SaveTargetDeliveryError.shellCommandFailed(String(localized: "Command is empty."))
        }

        do {
            _ = try await CustomCommandDeliveryRunner.run(
                command: trimmed,
                timeout: 10,
                context: CustomCommandDeliveryContext(transcript: text)
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw SaveTargetDeliveryError.shellCommandFailed(message)
        }

        logger.notice("Shell command delivered successfully")
        return String(localized: "Shell command executed.")
    }

    // MARK: - Sako strategy

    @MainActor
    private static func deliverSako(text: String) throws -> String {
        guard SakoClient.shared.send(text: text) else {
            throw SaveTargetDeliveryError.sakoFailed
        }
        logger.notice("Sent transcript to Sako")
        return String(localized: "Sent to Sako.")
    }

    // MARK: - Helpers

    /// Expands filename template tokens into a concrete base name (no extension).
    private static func expandedFilename(template: String, text: String) -> String {
        let now = Date()
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH-mm-ss"
        let datetimeFmt = DateFormatter(); datetimeFmt.dateFormat = "yyyy-MM-dd-HH-mm-ss"

        let slug = makeSlug(from: text)

        return template
            .replacingOccurrences(of: "{datetime}", with: datetimeFmt.string(from: now))
            .replacingOccurrences(of: "{date}", with: dateFmt.string(from: now))
            .replacingOccurrences(of: "{time}", with: timeFmt.string(from: now))
            .replacingOccurrences(of: "{slug}", with: slug)
    }

    /// First ~4 words, lowercased, diacritics folded, only [a-z0-9], joined by hyphens.
    private static func makeSlug(from text: String) -> String {
        let words = text
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(4)

        let cleaned = words.map { word in
            word.filter { $0.isLetter || $0.isNumber }
        }.filter { !$0.isEmpty }

        let slug = cleaned.joined(separator: "-")
        return slug.isEmpty ? "note" : slug
    }

    /// Resolve a file URL. If `append` is true and the file exists, return it as-is.
    /// Otherwise find an unused name by appending -2, -3, ...
    private static func resolvedFileURL(
        directory: URL,
        baseName: String,
        ext: String,
        append: Bool
    ) -> URL {
        let candidate = directory.appendingPathComponent("\(baseName).\(ext)")

        if append || !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        var counter = 2
        while true {
            let numbered = directory.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            if !FileManager.default.fileExists(atPath: numbered.path) {
                return numbered
            }
            counter += 1
        }
    }
}
