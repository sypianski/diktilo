import AppKit

/// The menu bar icon. While a recording is running it carries a red dot, so
/// the state is visible without opening the menu.
enum MenuBarIcon {
    private static let height: CGFloat = 22

    static func image(isRecording: Bool) -> NSImage {
        guard let base = NSImage(named: "menuBarIcon") else { return NSImage() }
        let ratio = base.size.height / base.size.width
        let size = NSSize(width: height / ratio, height: height)

        guard isRecording else {
            let image = (base.copy() as? NSImage) ?? base
            image.size = size
            return image
        }

        // A template image cannot hold a colour, so the recording icon is drawn
        // by hand and tinted for the current menu bar appearance.
        return NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            base.draw(in: rect)
            (isDark ? NSColor.white : NSColor.black).set()
            rect.fill(using: .sourceAtop)

            let dotSize: CGFloat = 8
            let dot = NSRect(x: rect.maxX - dotSize - 1, y: rect.maxY - dotSize - 1, width: dotSize, height: dotSize)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }
}
