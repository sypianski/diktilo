import SwiftUI

/// Destinations a recording can be saved to. They live with the modes because
/// a mode's "Save to Target" output and the targets' own finish shortcuts are
/// the only ways they are used.
struct ModesSaveTargetsSection: View {
    @ObservedObject private var saveTargetManager = SaveTargetManager.shared
    @State private var isShowingSaveTargets = false

    var body: some View {
        Section("Save Targets") {
            LabeledContent {
                Button("Manage…") {
                    isShowingSaveTargets = true
                }
            } label: {
                Text(saveTargetsSummary)
                Text("Files, URL schemes, shell commands or Notaro — each can have its own finish shortcut.")
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
