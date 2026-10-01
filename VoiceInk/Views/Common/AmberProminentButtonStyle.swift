import SwiftUI

/// Prominent action in the icon's amber. Replaces `.borderedProminent`, which
/// always draws white text on the accent: unreadable on amber (~1.9:1).
struct AmberProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(isEnabled ? AppTheme.Palette.onAmber : AppTheme.Action.disabledForeground)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background(
                Capsule()
                    .fill(isEnabled ? AppTheme.Palette.amber : AppTheme.Action.disabledFill)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }

    private var height: CGFloat {
        switch controlSize {
        case .mini: return 18
        case .small: return 22
        case .large: return 32
        case .extraLarge: return 38
        default: return 26
        }
    }

    private var fontSize: CGFloat {
        switch controlSize {
        case .mini, .small: return 11
        case .large, .extraLarge: return 14
        default: return 13
        }
    }

    private var horizontalPadding: CGFloat {
        switch controlSize {
        case .mini, .small: return 10
        case .large, .extraLarge: return 18
        default: return 14
        }
    }
}

extension ButtonStyle where Self == AmberProminentButtonStyle {
    static var amberProminent: AmberProminentButtonStyle { AmberProminentButtonStyle() }
}
