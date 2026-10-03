import AppKit
import Foundation
import os

// MARK: - Vimileto bridge
//
// The transcript edit window is provided by the standalone Vimileto app
// (bundle cc.sypianski.vimileto), not an in-process panel. Diktilo hands the
// (already enhanced) text to Vimileto over a small file + URL-scheme protocol
// and runs its own pipeline on the result:
//   • commit → clipboard   • worek → SakoClient   • cancel → nothing
//
// Protocol (mirror of Vimileto's IPCSession):
//   deliver:   open  vimileto://edit?session=<id>
//   payload:   ~/.cache/vimileto/ipc/<id>.{in,opts,out,result}
//   done:      Darwin notification cc.sypianski.vimileto.session.done
//
// If Vimileto is not installed the text is dropped onto the clipboard so it is
// never lost.
@MainActor
final class TranscriptEditManager {
    static let shared = TranscriptEditManager()

    /// Retained for API compatibility with older call sites / settings.
    static let vimEnabledKey = "EditWindowVimEnabled"

    private let logger = Logger(subsystem: "cc.sypianski.diktilo", category: "VimiletoBridge")
    private static let vimiletoBundleID = "cc.sypianski.vimileto"
    private static let doneNotification = "cc.sypianski.vimileto.session.done"

    private struct Pending {
        let id: String
        let previousApp: NSRunningApplication?
        let onDone: (() -> Void)?
    }
    private var pending: Pending?

    var isVisible: Bool { pending != nil }

    /// Whether an external editor app is installed to serve the Edit Window
    /// output mode. When false, `present(text:)` falls back to the clipboard.
    static var isExternalEditorInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: vimiletoBundleID) != nil
    }

    private init() {
        registerDarwinObserver()
        Self.sweepOrphans()
    }

    // MARK: Present

    /// Hand `text` to Vimileto for editing. `saveToWorek` offers the ⌥↵ Worek
    /// action. `onDone` fires once the session resolves (any outcome).
    func present(text: String, onDone: (() -> Void)? = nil, saveToWorek: Bool = true) {
        // A still-pending session means the previous edit never resolved
        // (Vimileto crashed or was force-quit): drop its stranded IPC files
        // before starting a new one so they don't accumulate.
        if let stale = pending {
            Self.cleanup(stale.id)
            pending = nil
        }

        let id = UUID().uuidString
        let dir = Self.ipcDir()

        do {
            try text.write(to: dir.appendingPathComponent("\(id).in"),
                           atomically: true, encoding: .utf8)
            let opts = try JSONSerialization.data(withJSONObject: ["worek": saveToWorek])
            try opts.write(to: dir.appendingPathComponent("\(id).opts"))
        } catch {
            logger.error("Vimileto IPC write failed: \(error.localizedDescription, privacy: .public)")
            _ = ClipboardManager.setClipboard(text)
            onDone?()
            return
        }

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.vimiletoBundleID) != nil,
              let url = URL(string: "vimileto://edit?session=\(id)") else {
            logger.warning("Vimileto.app not installed; falling back to clipboard.")
            _ = ClipboardManager.setClipboard(text)
            Self.cleanup(id)
            onDone?()
            return
        }

        pending = Pending(id: id,
                          previousApp: NSWorkspace.shared.frontmostApplication,
                          onDone: onDone)
        NSWorkspace.shared.open(url)
    }

    // MARK: Completion

    private func handleDone() {
        guard let p = pending else { return }
        let dir = Self.ipcDir()
        // Ordering guarantee: Vimileto writes .out before .result before posting.
        guard let resultRaw = try? String(contentsOf: dir.appendingPathComponent("\(p.id).result"),
                                          encoding: .utf8) else {
            return  // not our session (or not written yet) — keep waiting
        }
        let result = resultRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let outText = (try? String(contentsOf: dir.appendingPathComponent("\(p.id).out"),
                                   encoding: .utf8)) ?? ""

        pending = nil

        switch result {
        case "commit":
            if !ClipboardManager.setClipboard(outText) {
                logger.error("Failed to copy edited transcript to clipboard")
            }
            SoundManager.shared.playStopSound()
        case "worek":
            SakoClient.shared.send(text: outText)
            SoundManager.shared.playStopSound()
        default:
            break  // cancel
        }

        p.previousApp?.activate()
        Self.cleanup(p.id)
        p.onDone?()
    }

    // MARK: Darwin observer

    private func registerDarwinObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let mgr = Unmanaged<TranscriptEditManager>.fromOpaque(observer).takeUnretainedValue()
                mgr.notifyDoneFromDarwin()
            },
            Self.doneNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    // Darwin callbacks arrive outside actor isolation — hop to the main actor.
    nonisolated private func notifyDoneFromDarwin() {
        Task { @MainActor in self.handleDone() }
    }

    // MARK: Files

    private static func ipcDir() -> URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/vimileto/ipc", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cleanup(_ id: String) {
        let dir = ipcDir()
        for ext in ["in", "opts", "out", "result"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).\(ext)"))
        }
    }

    /// Remove IPC files left behind by sessions that never resolved (e.g.
    /// Vimileto crashed after we wrote `.in`/`.opts` but before posting done).
    /// Age-gated so an edit window open across an app relaunch is never touched.
    private static func sweepOrphans(olderThan maxAge: TimeInterval = 2 * 60 * 60) {
        let dir = ipcDir()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
