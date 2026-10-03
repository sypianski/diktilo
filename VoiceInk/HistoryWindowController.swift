import SwiftUI
import SwiftData
import AppKit

class HistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowController()

    private var historyWindow: NSWindow?
    private let windowIdentifier = NSUserInterfaceItemIdentifier("cc.sypianski.diktilo.historyWindow")
    private let windowAutosaveName = NSWindow.FrameAutosaveName("DiktiloHistoryWindowFrame")
    // Default matches the main window's content area (window width minus sidebar).
    private let defaultSize = NSSize(width: 730, height: AppWindowLayout.minimumHeight)
    private let minimumSize = NSSize(width: 600, height: 500)

    private override init() {
        super.init()
    }

    func showHistoryWindow(
        modelContainer: ModelContainer,
        engine: VoiceInkEngine,
        recordingShortcutManager: RecordingShortcutManager
    ) {
        if let existingWindow = historyWindow {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = createHistoryWindow(
            modelContainer: modelContainer,
            engine: engine,
            recordingShortcutManager: recordingShortcutManager
        )
        historyWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func createHistoryWindow(
        modelContainer: ModelContainer,
        engine: VoiceInkEngine,
        recordingShortcutManager: RecordingShortcutManager
    ) -> NSWindow {
        // Same view as the main window's History tab; inject everything its subtree
        // reads from the environment (AudioPlayerView, HistorySettingsPanel).
        let historyView = InlineHistoryView()
            .background(
                AppTheme.Surface.window
                    .ignoresSafeArea(.container, edges: .top)
            )
            .modelContainer(modelContainer)
            .environmentObject(engine)
            .environmentObject(engine.enhancementService!)
            .environmentObject(recordingShortcutManager)
            .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)

        let hostingController = NSHostingController(rootView: historyView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = String(localized: "History")
        window.identifier = windowIdentifier
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = minimumSize

        window.setFrameAutosaveName(windowAutosaveName)
        if !window.setFrameUsingName(windowAutosaveName) {
            window.center()
        }

        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == windowIdentifier else { return }

        historyWindow = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == windowIdentifier else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
