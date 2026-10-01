import Foundation
import SwiftUI

enum DashboardHeroHeadline {
    case calculatingProgress
    case startRecordingProgress
    case savedTime(String)
}

struct DashboardHeroCard: View {
    private static let headlineFont: Font = .system(size: 28, weight: .bold)
    private static let highlightedHeadlineFont: Font = .system(size: 28, weight: .semibold, design: .monospaced)

    let isLocked: Bool
    let headline: DashboardHeroHeadline
    let subtext: String
    let actionTitle: LocalizedStringKey
    let actionIcon: String
    let canViewInsights: Bool
    let actionHelp: String
    let actionAccessibilityLabel: String
    let onViewInsights: () -> Void

    @AppStorage(UserAddressForm.userDefaultsKey) private var addressForm = UserAddressForm.masculine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLocked {
                lockedInsightsPrompt
            } else {
                heroCopy
            }

            HStack(spacing: 12) {
                Button(action: onViewInsights) {
                    DashboardMomentumActionLabel(
                        title: actionTitle,
                        icon: actionIcon,
                        isPrimary: canViewInsights,
                        isLocked: !canViewInsights
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canViewInsights)
                .help(actionHelp)
                .accessibilityLabel(Text(actionAccessibilityLabel))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(DashboardImpactBackground())
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            headlineText
                .frame(maxWidth: 720, alignment: .leading)

            Text(subtext)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(DashboardMomentumBackground.subtext)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var headlineText: Text {
        Text(styledHeadline)
    }

    private var styledHeadline: AttributedString {
        let highlightedValue: String
        var text: AttributedString

        switch headline {
        case .calculatingProgress:
            highlightedValue = String(localized: "Diktilo progress")
            text = AttributedString(localized: "Calculating \(highlightedValue).")
        case .startRecordingProgress:
            highlightedValue = String(localized: "Diktilo progress")
            text = AttributedString(localized: "Start recording to build \(highlightedValue).")
        case .savedTime(let value):
            highlightedValue = value
            text = AttributedString(UserAddressForm.localizedFormat("You have saved %@ with Diktilo", highlightedValue, form: addressForm))
        }

        text.font = Self.headlineFont
        text.foregroundColor = DashboardMomentumBackground.headline

        // Marker-pen highlight; thin spaces keep the amber off the glyph edges.
        if let highlightedRange = text.range(of: highlightedValue) {
            var marked = AttributedString("\u{2009}\(highlightedValue)\u{2009}")
            marked.font = Self.highlightedHeadlineFont
            marked.foregroundColor = AppTheme.Palette.onAmber
            marked.backgroundColor = DashboardMomentumBackground.accent
            text.replaceSubrange(highlightedRange, with: marked)
        }

        return text
    }

    private var lockedInsightsPrompt: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.Palette.chip)

                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DashboardMomentumBackground.headline)
            }
            .frame(width: 42, height: 42)

            Text("Continue using Diktilo to unlock stats and insights.")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(DashboardMomentumBackground.headline)
                .frame(maxWidth: 540, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardMomentumActionLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool
    var isLocked = false

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .lineLimit(2)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 18)
        .frame(minHeight: 36)
        .background(Capsule().fill(isLocked ? AppTheme.Palette.chip : .clear))
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1.5)
        )
        .contentShape(Capsule())
    }

    private var foregroundColor: Color {
        isLocked ? DashboardMomentumBackground.subtext : DashboardMomentumBackground.headline
    }

    private var borderColor: Color {
        isPrimary ? DashboardMomentumBackground.headline : AppTheme.Palette.rule
    }
}

/// Top and bottom perforation: the hero reads as a strip torn off the tape.
private struct DashboardImpactBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            PerforationRule()
            Spacer(minLength: 0)
            PerforationRule()
        }
    }
}

private enum DashboardMomentumBackground {
    static let accent = AppTheme.Palette.amber
    static let headline = AppTheme.Palette.ink
    static let subtext = AppTheme.Palette.inkSecondary
}
