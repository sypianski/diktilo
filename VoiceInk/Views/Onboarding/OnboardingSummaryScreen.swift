import SwiftUI

/// Last screen: what was chosen, and an invitation to the guide. Nothing
/// opens by itself; "See the guide" is the only way onboarding hands over to it.
struct OnboardingSummaryScreen: View {
    struct Row: Identifiable {
        let id: String
        let systemImage: String
        let title: LocalizedStringKey
        let value: String
    }

    let contentMaxWidth: CGFloat
    let rows: [Row]
    let onBack: () -> Void
    let onSeeGuide: () -> Void
    let onStart: () -> Void

    var body: some View {
        OnboardingStepScreen(
            stage: .summary,
            contentMaxWidth: contentMaxWidth
        ) {
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    HStack(spacing: 14) {
                        Image(systemName: row.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.Text.secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(AppTheme.Surface.controlActive)
                            )

                        Text(row.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.Text.primary)

                        Spacer(minLength: 12)

                        Text(row.value)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.Text.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppMaterialCardBackground(cornerRadius: 10))
                }
            }
        } bottomBar: {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.Action.secondaryForeground)
                        .frame(width: 132, height: 42)
                        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.control))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: onSeeGuide) {
                    Text("See the Guide")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.Action.secondaryForeground)
                        .padding(.horizontal, 20)
                        .frame(minWidth: 132, minHeight: 42)
                        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.control))
                }
                .buttonStyle(.plain)

                Button(action: onStart) {
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.Action.primaryForeground)
                        .padding(.horizontal, 20)
                        .frame(minWidth: 132, minHeight: 42)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .fill(AppTheme.Action.primaryFill)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
