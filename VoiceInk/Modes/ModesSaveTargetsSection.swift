import SwiftUI

/// Destinations a recording can be saved to. They live with the modes because
/// a mode's "Save to Target" output and the targets' own finish shortcuts are
/// the only ways they are used.
struct ModesSaveTargetsSection: View {
    @ObservedObject private var saveTargetManager = SaveTargetManager.shared
    @State private var isShowingSaveTargets = false

    @AppStorage(AdvancedFeature.saveTargets.defaultsKey) private var saveTargetsEnabled = AdvancedFeature.defaultValue

    var body: some View {
        FeatureGateSection(
            "Save Targets",
            summary: "Save Targets send a recording somewhere other than the clipboard or the cursor: a file, a URL scheme or a shell command. Each can have its own shortcut that finishes the recording.",
            infoMessage: "A shell command runs code with your user's permissions, so add only commands you trust. Turning Save Targets off only suspends them: your targets and their shortcuts are kept and come back when you turn it on again.",
            mode: .toggle(isOn: $saveTargetsEnabled)
        ) {
            LabeledContent {
                Button("Manage…") {
                    isShowingSaveTargets = true
                }
            } label: {
                Text(saveTargetsSummary)
            }
        }
        .sheet(isPresented: $isShowingSaveTargets) {
            NavigationStack {
                SaveTargetsSettingsView()
                    .navigationTitle("Save Targets")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingSaveTargets = false }
                        }
                    }
            }
            .frame(minWidth: 500, minHeight: 420)
        }
    }

    private var saveTargetsSummary: String {
        let names = saveTargetManager.targets.map(\.name)
        guard !names.isEmpty else { return String(localized: "No save targets yet") }
        return names.joined(separator: ", ")
    }
}
