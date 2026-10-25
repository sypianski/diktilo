import SwiftUI

/// Text improvement is optional: continuing without a verified key just leaves
/// it off, so there is no warning dialog, only a quiet "Skip this step".
struct OnboardingAPIScreen: View {
    @ObservedObject var aiService: AIService

    let contentMaxWidth: CGFloat
    let providerOptions: [AIProvider]
    @Binding var selectedProvider: AIProvider
    let isSelectedProviderVerified: Bool
    let onVerificationChanged: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScreen(
            stage: .api,
            contentMaxWidth: contentMaxWidth
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Without a key, text improvement and AI modes stay off. You can set it up later in AI Models.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AIProviderVerificationCard(
                    aiService: aiService,
                    providerOptions: providerOptions,
                    selectedProvider: $selectedProvider,
                    onVerificationChanged: onVerificationChanged
                )

                if !isSelectedProviderVerified {
                    Button("Skip this step", action: onContinue)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: true,
                onLeading: onBack,
                onPrimary: onContinue
            )
        }
    }
}
