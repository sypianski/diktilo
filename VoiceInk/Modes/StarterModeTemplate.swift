import Foundation

enum StarterModeKind: String, CaseIterable, Identifiable {
    case clean

    var id: String { rawValue }
}

struct StarterModeTemplate: Identifiable {
    let kind: StarterModeKind
    let id: UUID
    let name: String
    let icon: ModeIcon
    let description: String
    let guidance: String
    let promptId: UUID?
    let outputMode: OutputMode
    let usesAIEnhancement: Bool
    let useSelectedTextContext: Bool
    let useScreenCapture: Bool
    let isDefault: Bool

    var featureLabels: [String] {
        var labels = ["Transcription", "Realtime"]

        if usesAIEnhancement {
            labels.append("AI")
        } else {
            labels.append("No AI")
        }

        if outputMode == .respond {
            labels.append("Respond")
        } else {
            labels.append("Paste")
        }

        return labels
    }
}

/// Onboarding installs a single mode: "Paste", the default mode the main
/// recording shortcut runs. A fresh install gets it (plus "Copy") even without
/// onboarding — see `DefaultModeSeeder`, which uses the same id so the two
/// never duplicate.
enum StarterModeCatalog {
    static let templates: [StarterModeTemplate] = [
        StarterModeTemplate(
            kind: .clean,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: String(localized: "Paste"),
            icon: .symbol("doc.on.clipboard"),
            description: String(localized: "Fast transcription with no AI enhancement."),
            guidance: String(localized: "Use this when you want the quickest possible voice-to-text result. It records with your configured transcription model and pastes the transcript as-is."),
            promptId: nil,
            outputMode: .paste,
            usesAIEnhancement: false,
            useSelectedTextContext: false,
            useScreenCapture: false,
            isDefault: true
        )
    ]

    static var ids: Set<UUID> {
        Set(templates.map(\.id))
    }
}
