import SwiftUI

/// Shortcut, sample text and result field on one screen. The card holds the
/// shortcut control, so there is no separate intro step.
struct OnboardingExperienceScreen: View {
    let step: OnboardingExperienceStep
    let shortcutAction: ShortcutAction
    let hasShortcut: Bool
    @Binding var text: String
    let isReady: Bool
    let isComplete: Bool
    let onBack: () -> Void
    let onAdvance: () -> Void
    let onShortcutChanged: () -> Void
    let onAppear: () -> Void

    var body: some View {
        OnboardingStepScreen(
            systemImage: step.systemImage,
            title: step.title,
            subtitle: step.subtitle,
            contentMaxWidth: 700,
            showsHeader: true
        ) {
            OnboardingExperienceCard(
                step: step,
                shortcutAction: shortcutAction,
                hasShortcut: hasShortcut,
                text: $text,
                onShortcutChanged: onShortcutChanged
            )
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: isReady && isComplete,
                onLeading: onBack,
                onPrimary: onAdvance
            )
        }
        .onAppear(perform: onAppear)
    }
}
