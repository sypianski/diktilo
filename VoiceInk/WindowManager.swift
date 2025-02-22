import SwiftUI
import AppKit

class WindowManager {
    static let shared = WindowManager()
    
    private init() {}
    
    func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.title = "VoiceInk"
        
        // Add additional window configuration for better state management
        window.collectionBehavior = [.fullScreenPrimary]
        window.setFrameAutosaveName("MainWindow")  // Save window position and size
        
        // Ensure proper window level and ordering
        window.level = .normal
        window.orderFrontRegardless()
    }
    
    func createMainWindow(contentView: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        configureWindow(window)
        window.contentView = contentView
        
        // Set up window delegate to handle window state changes
        let delegate = WindowStateDelegate()
        window.delegate = delegate
        
        return window
    }
}

// Add window delegate to handle window state changes
class WindowStateDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Ensure window is properly hidden when closed
        window.orderOut(nil)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure window is properly activated
        guard let window = notification.object as? NSWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
} 
