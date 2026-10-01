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
    @State private var activePanel: PanelType?
    @State private var panelID = UUID()
    @State private var modePendingDeletion: OutputProfile?

    private enum PanelType {
        case configuration(ConfigurationMode)
        case order
    }

    private var isPanelOpen: Bool {
        activePanel != nil
    }

    private var orderButton: some View {
        AppIconButton(
            systemName: "arrow.up.arrow.down",
            help: "Mode Order"
        ) {
            openOrderPanel()
        }
    }

    private var addModeButton: some View {
        Button {
            openPanel(mode: .add)
        } label: {
            Label("Add Mode", systemImage: "plus")
        }
        .buttonStyle(.amberProminent)
        .controlSize(.small)
    }

    // Order: the shortcut that starts every recording, the modes it can end
    // in, then the global output defaults those modes build on.
    var body: some View {
            VStack(spacing: 0) {
                AppScreenHeader(
                    title: "Keyboard Shortcuts",
                    infoMessage: "Modes help you set up Diktilo for different writing tasks, workflows, and scenarios."
                ) {
                    orderButton
                }

                Form {
                    MainShortcutSection(modeManager: modeManager)

                    modesSection

                    ModesPastingSection()

                    ModesSaveTargetsSection()
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .confirmationDialog(
                "Delete Mode?",
                isPresented: Binding(
                    get: { modePendingDeletion != nil },
                    set: { if !$0 { modePendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: modePendingDeletion
            ) { config in
                Button("Delete", role: .destructive) {
                    modeManager.removeConfiguration(with: config.id)
                    modePendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { modePendingDeletion = nil }
            } message: { config in
                Text(String(format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."), config.name))
            }
            .sidePanel(isPresented: .init(
                get: { isPanelOpen },
                set: { if !$0 { closePanel() } }
            ), dismissOnExitCommand: false) {
                switch activePanel {
                case .configuration(let mode)?:
                    OutputProfileEditorView(mode: mode, modeManager: modeManager, onDismiss: closePanel)
                        .environmentObject(modeWarmupStore)
                        .id(panelID)
                case .order?:
                    OutputProfileSettingsPanelView(modeManager: modeManager, onDismiss: closePanel)
                case nil:
                    EmptyView()
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
                    addModeButton
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach($modeManager.configurations) { $config in
                    ConfigurationRow(
                        config: $config,
                        isEditing: false,
                        modeManager: modeManager,
                        onEditConfig: { config in
                            openPanel(mode: .edit(config))
                        },
                        onDelete: { config in
                            modePendingDeletion = config
                        }
                    )
                }
            }
        } header: {
            HStack {
                Text("Modes")
                Spacer()
                if !modeManager.configurations.isEmpty {
                    addModeButton
                }
            }
        } footer: {
            Text("A mode decides where the text goes and whether AI rewrites it. Finish a recording with a mode's shortcut, or let an app or website trigger pick the mode.")
        }
    }

    private func openPanel(mode: ConfigurationMode) {
        panelID = UUID()
        activePanel = .configuration(mode)
    }

    private func closePanel() {
        activePanel = nil
    }

    private func openOrderPanel() {
        activePanel = .order
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
