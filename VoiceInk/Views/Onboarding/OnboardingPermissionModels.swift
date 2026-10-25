import SwiftUI

enum OnboardingStage: String, CaseIterable {
    case trust
    case permissions
    case model
    case api
    case experience
    case summary

    var stepNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    static var stepCount: Int {
        allCases.count
    }

    var systemImage: String {
        switch self {
        case .trust:
            return "lock.shield"
        case .permissions:
            return "mic"
        case .model:
            return "captions.bubble"
        case .api:
            return "checkmark.seal"
        case .experience:
            return "square.grid.2x2.fill"
        case .summary:
            return "checkmark.circle"
        }
    }

    var title: String {
        switch self {
        case .trust:
            return String(localized: "Diktilo is Open Source")
        case .permissions:
            return String(localized: "Allow Permissions")
        case .model:
            return String(localized: "Choose Speech Recognition")
        case .api:
            return String(localized: "Text Improvement (optional)")
        case .experience:
            return String(localized: "Experience Diktilo")
        case .summary:
            return String(localized: "All Set")
        }
    }

    var subtitle: String {
        switch self {
        case .trust:
            return UserAddressForm.localized("Diktilo is private by default. No data leaves your device unless you opt in.")
        case .permissions:
            return String(localized: "Allow Diktilo to work across all your apps, then pick the microphone for recordings.")
        case .model:
            return String(localized: "Speech recognition turns your voice into text. Run it on your Mac or connect a cloud provider.")
        case .api:
            return String(localized: "An AI model can improve the transcript: fix punctuation, rewrite, answer. Without a key this stays off.")
        case .experience:
            return String(localized: "Choose a shortcut and dictate a sample sentence.")
        case .summary:
            return String(localized: "Here is what you chose. Everything can be changed later in the app.")
        }
    }
}

enum OnboardingPermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility

    var id: String { rawValue }

    static var required: [OnboardingPermissionKind] {
        [.microphone, .accessibility]
    }

    var isRequired: Bool {
        Self.required.contains(self)
    }

    var descriptor: OnboardingPermissionDescriptor {
        switch self {
        case .microphone:
            return OnboardingPermissionDescriptor(
                title: "Microphone",
                subtitle: String(localized: "Diktilo uses your microphone to capture your voice.")
            )

        case .accessibility:
            return OnboardingPermissionDescriptor(
                title: String(localized: "Accessibility"),
                subtitle: String(localized: "Diktilo uses Accessibility to type transcriptions directly into any app.")
            )
        }
    }
}

struct OnboardingPermissionDescriptor {
    let title: String
    let subtitle: String
}

enum OnboardingPermissionStatus: Equatable {
    case granted
    case needsAccess
    case denied
    case restricted
    case unknown

    var isGranted: Bool {
        self == .granted
    }

    var requiresSettings: Bool {
        self == .denied || self == .restricted
    }

    var label: String {
        switch self {
        case .granted:
            return String(localized: "Granted")
        case .needsAccess:
            return String(localized: "Needs access")
        case .denied:
            return String(localized: "Denied")
        case .restricted:
            return String(localized: "Restricted")
        case .unknown:
            return String(localized: "Unknown")
        }
    }

    var color: Color {
        switch self {
        case .granted:
            return AppTheme.Text.secondary
        case .needsAccess:
            return AppTheme.Text.secondary
        case .denied, .restricted:
            return AppTheme.Status.error
        case .unknown:
            return AppTheme.Text.secondary
        }
    }
}

enum PrivacySettingsPane {
    case microphone
    case accessibility

    var urlString: String {
        switch self {
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}
