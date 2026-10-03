import AppKit
import ApplicationServices

/// The display the user is working on, used to place the recorder and other
/// shortcut-triggered panels. `NSScreen.main` follows Diktilo's own key window,
/// which can sit on a different display than the app being dictated into.
@MainActor
enum ActiveScreen {
    static func current() -> NSScreen? {
        focusedWindowScreen() ?? mouseScreen() ?? NSScreen.main
    }

    /// Screen holding the center of the frontmost app's focused window. Uses the
    /// Accessibility permission Diktilo already needs for pasting.
    private static func focusedWindowScreen() -> NSScreen? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return NSApp.keyWindow?.screen
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // A hung frontmost app must not delay showing the recorder.
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let window = windowRef as! AXUIElement
        AXUIElementSetMessagingTimeout(window, messagingTimeout)

        guard let origin = pointValue(kAXPositionAttribute, of: window),
              let size = sizeValue(kAXSizeAttribute, of: window),
              let primary = NSScreen.screens.first else {
            return nil
        }

        // AX frames use a top-left origin anchored to the primary display.
        let center = CGPoint(
            x: origin.x + size.width / 2,
            y: primary.frame.maxY - origin.y - size.height / 2
        )
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private static func mouseScreen() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    private static let messagingTimeout: Float = 0.2

    private static func pointValue(_ attribute: String, of element: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(attribute, of: element), AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func sizeValue(_ attribute: String, of element: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(attribute, of: element), AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private static func axValue(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let valueRef, CFGetTypeID(valueRef) == AXValueGetTypeID() else {
            return nil
        }
        return (valueRef as! AXValue)
    }
}
