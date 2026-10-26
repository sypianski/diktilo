import SwiftUI

enum FeatureGateMode {
    case collapsible(isExpanded: Binding<Bool>)
    case toggle(isOn: Binding<Bool>)
}

/// Section for a hidden-by-default advanced feature: title, one-sentence
/// summary, optional InfoTip, and either
/// - `.collapsible`: the feature works; only its details fold away, or
/// - `.toggle`: the feature is suspended while off (its settings are kept)
///   and its content appears once switched on.
/// Drop it into a `Form` with `.formStyle(.grouped)`.
struct FeatureGateSection<Content: View>: View {
    private let title: LocalizedStringKey
    private let summary: LocalizedStringKey
    private let infoMessage: LocalizedStringKey?
    private let mode: FeatureGateMode
    private let content: () -> Content

    @State private var isToggleExpanded = true

    init(
        _ title: LocalizedStringKey,
        summary: LocalizedStringKey,
        infoMessage: LocalizedStringKey? = nil,
        mode: FeatureGateMode,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.infoMessage = infoMessage
        self.mode = mode
        self.content = content
    }

    private func collapsedNote(_ isExpanded: Bool) -> LocalizedStringKey? {
        if isExpanded { return nil }
        return "Active — details collapsed"
    }

    private func disabledNote(_ isOn: Bool) -> LocalizedStringKey? {
        if isOn { return nil }
        return "Disabled — settings are kept"
    }

    var body: some View {
        Section {
            switch mode {
            case .collapsible(let isExpanded):
                ExpandableSettingsRow(
                    title: title,
                    isExpanded: isExpanded,
                    isEnabled: nil,
                    summary: summary,
                    statusNote: collapsedNote(isExpanded.wrappedValue),
                    infoMessage: infoMessage,
                    content: content
                )
            case .toggle(let isOn):
                ExpandableSettingsRow(
                    title: title,
                    isExpanded: $isToggleExpanded,
                    isEnabled: isOn,
                    summary: summary,
                    statusNote: disabledNote(isOn.wrappedValue),
                    infoMessage: infoMessage,
                    content: content
                )
            }
        }
    }
}

private struct FeatureGateSectionPreview: View {
    @State private var expanded = false
    @State private var enabled = false

    var body: some View {
        Form {
            FeatureGateSection(
                "Collapsible feature",
                summary: "One sentence about what this is.",
                infoMessage: "More detail in a tip.",
                mode: .collapsible(isExpanded: $expanded)
            ) {
                Text("Details")
            }
            FeatureGateSection(
                "Switchable feature",
                summary: "One sentence about what this is.",
                mode: .toggle(isOn: $enabled)
            ) {
                Text("Details")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
    }
}

#Preview {
    FeatureGateSectionPreview()
}
