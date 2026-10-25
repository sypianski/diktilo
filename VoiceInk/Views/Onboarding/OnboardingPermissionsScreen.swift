import SwiftUI

struct OnboardingPermissionsScreen: View {
    let contentMaxWidth: CGFloat
    let isComplete: Bool
    let isMicrophoneSelected: Bool
    let isMicrophoneGranted: Bool
    let activePermission: OnboardingPermissionKind
    let stepNumber: (OnboardingPermissionKind) -> Int
    let status: (OnboardingPermissionKind) -> OnboardingPermissionStatus
    let isLocked: (OnboardingPermissionKind) -> Bool
    let actionTitle: (OnboardingPermissionKind) -> String
    let onSelect: (OnboardingPermissionKind) -> Void
    let onAction: (OnboardingPermissionKind) -> Void
    let onMicrophoneSelected: () -> Void
    let onBack: () -> Void
    let onRecheck: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScreen(
            stage: .permissions,
            contentMaxWidth: contentMaxWidth
        ) {
            VStack(spacing: 16) {
                permissionList

                if isMicrophoneGranted {
                    OnboardingMicrophonePicker(onSelectionSaved: onMicrophoneSelected)
                        .transition(.opacity)
                }

                if !isComplete {
                    Button("Recheck", action: onRecheck)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.Text.secondary)
                }
            }
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: isComplete && isMicrophoneSelected,
                onLeading: onBack,
                onPrimary: onContinue
            )
        }
    }

    private var permissionList: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingPermissionKind.allCases) { permission in
                PermissionStepRow(
                    stepNumber: stepNumber(permission),
                    descriptor: permission.descriptor,
                    status: status(permission),
                    isActive: !isComplete && activePermission == permission,
                    isLocked: isLocked(permission),
                    actionTitle: actionTitle(permission),
                    onSelect: {
                        guard !isLocked(permission) else { return }
                        onSelect(permission)
                    },
                    onAction: {
                        onAction(permission)
                    }
                )
            }
        }
    }
}
