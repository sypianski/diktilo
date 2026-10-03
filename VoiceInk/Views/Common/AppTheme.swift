import SwiftUI

enum AppTheme {
    /// Colours sampled from the app icon: amber tile, charcoal slot, paper tape.
    /// Light appearance is the paper ("Taśma"); dark is the slot's charcoal.
    /// The amber itself lives in the AccentColor asset so system controls pick it up.
    enum Palette {
        static let amber = Color(nsColor: NSColor(rgb: 0xFDAE2C))
        /// Text on amber. White on amber is ~1.9:1, this is ~7.9:1.
        static let onAmber = Color(nsColor: NSColor(rgb: 0x2B2724))
        static let paper = dynamic(light: 0xFBF4E8, dark: 0x1E1B18)
        static let sidebar = dynamic(light: 0xF3EBDD, dark: 0x25211D)
        static let raised = dynamic(light: 0xFFFCF5, dark: 0x2A2622)
        static let chip = dynamic(light: 0xEFE6D6, dark: 0x2D2925)
        static let rule = dynamic(light: 0xD3C8B5, dark: 0x3A3531)
        static let ink = dynamic(light: 0x33302C, dark: 0xF3ECE0)
        /// Amber legible as text or a glyph: amber on paper is only ~1.7:1.
        static let amberInk = dynamic(light: 0x9A5B00, dark: 0xFDAE2C)
        static let inkSecondary = dynamic(light: 0x6F675D, dark: 0xB5AA9C)
        /// Live waveform: ink on paper, amber on charcoal.
        static let waveform = dynamic(light: 0x33302C, dark: 0xFDAE2C)

        /// Dashed rule, echoing the perforation of the icon's paper tape.
        static let perforation = StrokeStyle(lineWidth: 1.5, dash: [5, 4])

        private static func dynamic(light: UInt32, dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(rgb: dark)
                    : NSColor(rgb: light)
            })
        }
    }

    enum Accent {
        static let primary = Color.accentColor
        /// Use for accent-coloured text and glyphs; `primary` is for fills.
        static let text = Palette.amberInk
        static let fillSubtle = primary.opacity(0.10)
        static let fill = primary.opacity(0.14)
        static let fillStrong = primary.opacity(0.28)
        static let border = primary.opacity(0.40)
        static let disabled = primary.opacity(0.50)
        static let foreground = primary.opacity(0.65)
        static let strong = primary.opacity(0.80)
        static let shadow = primary.opacity(0.20)
    }

    enum Surface {
        static let card = Palette.chip.opacity(0.70)
        static let materialCard = Palette.raised
        static let subtle = Color.primary.opacity(0.06)
        static let controlActive = Color.secondary.opacity(0.14)
        static let control = Color(nsColor: .controlBackgroundColor)
        static let window = Palette.paper
        static let sidebar = Palette.sidebar
        static let sidePanelOverlay = Palette.paper.opacity(0.50)
        static let clear = Color.clear
    }

    enum Border {
        static let subtle = Palette.rule.opacity(0.60)
        static let card = Palette.rule.opacity(0.85)
        static let control = Palette.rule
        static let tint = Color.primary.opacity(0.12)
        static let sidePanelOuter = Color.white.opacity(0.12)
    }

    enum Selection {
        static let fill = Color.primary.opacity(0.10)
        static let border = Color.primary.opacity(0.14)
        static let foreground = Color.primary.opacity(0.78)
    }

    enum Status {
        static let success = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let positive = Color(nsColor: .systemGreen)
        static let info = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.75)
        static let infoStrong = Color(nsColor: .systemBlue)
        static let warning = Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85)
        static let warningStrong = Color(nsColor: .systemOrange)
        static let error = Color(nsColor: .systemRed)
    }

    enum Data {
        static let transcript = Color.indigo
        static let audio = Color.teal
        static let enhancement = Color.mint
        static let purple = Color(nsColor: .systemPurple)
        static let yellow = Color(nsColor: .systemYellow)
        static let orange = Color(nsColor: .systemOrange)
    }

    enum Sidebar {
        static let dashboard = Color(nsColor: .systemOrange)
        static let modes = Color(nsColor: .systemIndigo)
        static let models = Color(nsColor: .systemBrown)
        static let audio = Color(nsColor: .systemPink)
        static let dictionary = Color(nsColor: .systemBlue)
        static let transcribeAudio = Color(red: 0.86, green: 0.32, blue: 0.27)
        static let fallback = Color(nsColor: .systemGray)
    }

    enum Waveform {
        static let hoverBubble = Color.primary.opacity(0.74)
        static let hoverMarker = Color.primary.opacity(0.68)
        static let playedLower = Color.primary
        static let playedUpper = Color.primary.opacity(0.80)
        static let unplayedLower = Color.primary.opacity(0.30)
        static let unplayedUpper = Color.primary.opacity(0.20)
    }

    enum Text {
        static let primary = Palette.ink
        static let secondary = Palette.inkSecondary
        static let muted = secondary.opacity(0.70)
        static let disabled = Color(nsColor: .disabledControlTextColor)
        static let onAccent = Palette.onAmber
    }

    enum NativeText {
        static let primary = NSColor.labelColor
    }

    enum Action {
        static let primaryFill = Accent.primary
        static let primaryForeground = Text.onAccent
        static let secondaryForeground = Text.primary
        static let disabledFill = Surface.controlActive
        static let disabledForeground = Text.disabled
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 12
        static let pill: CGFloat = 22
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
