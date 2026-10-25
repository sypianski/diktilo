import SwiftUI
import SwiftData

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

enum ConfigurationMode: Hashable {
    case add
    case edit(OutputProfile)
    
    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .add:
            hasher.combine(0)
        case .edit(let config):
            hasher.combine(1)
            hasher.combine(config.id)
        }
    }
    
    static func == (lhs: ConfigurationMode, rhs: ConfigurationMode) -> Bool {
        switch (lhs, rhs) {
        case (.add, .add):
            return true
        case (.edit(let lhsConfig), .edit(let rhsConfig)):
            return lhsConfig.id == rhsConfig.id
        default:
            return false
        }
    }
}

enum ConfigurationType {
    case application
    case website
}

struct OutputProfileView: View {
    @StateObject private var modeManager = OutputProfileManager.shared
    @StateObject private var modeWarmupStore = OutputProfileFormWarmupStore.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var tab: Tab = .modes
    @State private var activeConfiguration: ConfigurationMode?
    @State private var panelID = UUID()

    /// Everyone needs the first tab; how text is pasted and where it is saved
    /// are set once and rarely touched, so they sit one click away.
    private enum Tab: Hashable {
        case modes
        case delivery
    }

    private var isPanelOpen: Bool {
        activeConfiguration != nil
    }

    // Order: the shortcut that starts every recording, then the modes it can
    // end in. Global paste defaults and save targets are on the second tab.
    var body: some View {
        VStack(spacing: 0) {
            AppScreenHeader(
                title: "Shortcuts and Modes",
                infoMessage: "Modes help you set up Diktilo for different writing tasks, workflows, and scenarios."
            )

            Picker("", selection: $tab) {
                Text("Shortcuts and Modes").tag(Tab.modes)
                Text("Pasting and Save Targets").tag(Tab.delivery)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 6)

            Form {
                switch tab {
                case .modes:
                    MainShortcutSection(modeManager: modeManager)

                    modesSection
                case .delivery:
                    ModesPastingSection()

                    ModesSaveTargetsSection()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sidePanel(isPresented: .init(
            get: { isPanelOpen },
            set: { if !$0 { closePanel() } }
        ), dismissOnExitCommand: false) {
            if let mode = activeConfiguration {
                OutputProfileEditorView(mode: mode, modeManager: modeManager, onDismiss: closePanel)
                    .environmentObject(modeWarmupStore)
                    .id(panelID)
            }
        }
        .onAppear {
            modeWarmupStore.configure(
                aiService: aiService,
                enhancementService: enhancementService,
                transcriptionModelManager: transcriptionModelManager
            )
        }
    }

    private var modesSection: some View {
        Section {
            if modeManager.configurations.isEmpty {
                VStack(spacing: 8) {
                    Text("No Modes Yet")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add a mode to choose what happens with the text: paste it, copy it, save it or rewrite it with AI.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            ModesTableView(
                modeManager: modeManager,
                onEdit: { openPanel(mode: .edit($0)) },
                onAdd: { openPanel(mode: .add) }
            )
        } header: {
            Text("Modes")
        } footer: {
            Text("A mode decides where the text goes and whether AI rewrites it. Finish a recording with a mode's shortcut, or let an app or website trigger pick the mode. During recording, ⌥1–⌥0 switch the modes in this order.")
        }
    }

    private func openPanel(mode: ConfigurationMode) {
        panelID = UUID()
        activeConfiguration = mode
    }

    private func closePanel() {
        activeConfiguration = nil
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}
