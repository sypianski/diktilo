import SwiftUI
import UniformTypeIdentifiers

/// The list of modes as a table: order and ⌥ number, name, where the text
/// goes, AI, triggers, finish shortcut and the on/off switch. A row opens the
/// editor; dragging the handle reorders; the last row adds a mode. Deleting a
/// mode lives in the editor.
struct ModesTableView: View {
    @ObservedObject var modeManager: OutputProfileManager
    let onEdit: (OutputProfile) -> Void
    let onAdd: () -> Void

    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var draggedID: UUID?

    private enum Column {
        static let handle: CGFloat = 44
        static let output: CGFloat = 130
        static let ai: CGFloat = 130
        static let triggers: CGFloat = 70
        static let shortcut: CGFloat = 90
        static let toggle: CGFloat = 44
    }

    /// ⌥1…⌥9, ⌥0: the position among enabled modes, the same list the recorder panel uses.
    private func quickSwitchLabel(for config: OutputProfile) -> String? {
        guard let index = modeManager.enabledConfigurations.firstIndex(where: { $0.id == config.id }),
              index < 10 else { return nil }
        return "⌥" + (index == 9 ? "0" : "\(index + 1)")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !modeManager.configurations.isEmpty {
                headerRow
                Divider().opacity(0.5)
            }

            ForEach(modeManager.configurations) { config in
                ModesTableRow(
                    config: config,
                    quickSwitch: quickSwitchLabel(for: config),
                    aiTitle: aiTitle(for: config),
                    isDragged: draggedID == config.id,
                    modeManager: modeManager,
                    onEdit: { onEdit(config) }
                )
                .onDrag {
                    draggedID = config.id
                    return NSItemProvider(object: config.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ModesTableDropDelegate(
                        item: config,
                        modeManager: modeManager,
                        draggedID: $draggedID
                    )
                )

                Divider().opacity(0.35)
            }

            addRow
        }
        .onDrop(of: [UTType.text], delegate: ModesTableResetDelegate(draggedID: $draggedID))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: Column.handle, height: 1)
            columnTitle("Mode")
                .frame(maxWidth: .infinity, alignment: .leading)
            columnTitle("Output").frame(width: Column.output, alignment: .leading)
            columnTitle("AI").frame(width: Column.ai, alignment: .leading)
            columnTitle("Triggers").frame(width: Column.triggers, alignment: .leading)
            columnTitle("Shortcut").frame(width: Column.shortcut, alignment: .leading)
            Color.clear.frame(width: Column.toggle, height: 1)
        }
        .padding(.vertical, 6)
    }

    private func columnTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var addRow: some View {
        Button(action: onAdd) {
            Label("Add Mode", systemImage: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.Text.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.Palette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func aiTitle(for config: OutputProfile) -> String? {
        guard config.isAIEnhancementEnabled else { return nil }
        let prompt = enhancementService.allPrompts.first { $0.id.uuidString == config.selectedPrompt }
        return prompt?.title ?? String(localized: "On")
    }
}

private struct ModesTableRow: View {
    let config: OutputProfile
    let quickSwitch: String?
    let aiTitle: String?
    let isDragged: Bool
    let modeManager: OutputProfileManager
    let onEdit: () -> Void

    @State private var isHovering = false

    private var shortcut: Shortcut? {
        ShortcutStore.shortcut(for: .profile(config.id))
    }

    private var triggerCount: Int {
        config.allAppConfigs.count + config.allURLConfigs.count + config.triggerWords.count
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Text(quickSwitch ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if config.isDefault {
                    Label("Main Shortcut", systemImage: "keyboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.Accent.text)
                        .help("The main shortcut runs this mode when no app or website trigger matches.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Label(config.outputMode.displayName, systemImage: config.outputMode.iconName)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            Group {
                if let aiTitle {
                    Label(aiTitle, systemImage: "sparkles")
                } else {
                    Text("–")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(aiTitle == nil ? .secondary : .primary)
            .lineLimit(1)
            .frame(width: 130, alignment: .leading)

            Text(triggerCount == 0 ? "–" : "\(triggerCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(triggerCount == 0 ? .secondary : .primary)
                .frame(width: 70, alignment: .leading)

            Text(shortcut?.displayString ?? "–")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(shortcut == nil ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            Group {
                if config.isDefault {
                    Color.clear
                } else {
                    Toggle("", isOn: Binding(
                        get: { config.isEnabled },
                        set: { newValue in
                            if newValue {
                                modeManager.enableConfiguration(with: config.id)
                            } else {
                                modeManager.disableConfiguration(with: config.id)
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: AppTheme.Accent.primary))
                    .labelsHidden()
                    .help(config.isEnabled ? LocalizedStringKey("Turn this mode off") : LocalizedStringKey("Turn this mode on"))
                }
            }
            .frame(width: 44)
        }
        .padding(.vertical, 9)
        .background(isHovering ? AppTheme.Surface.controlActive.opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { isHovering = $0 }
        .opacity(isDragged ? 0.5 : (config.isEnabled ? 1 : 0.7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(config.name)
        .accessibilityAddTraits(.isButton)
    }
}

private struct ModesTableDropDelegate: DropDelegate {
    let item: OutputProfile
    let modeManager: OutputProfileManager
    @Binding var draggedID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              draggedID != item.id,
              let fromIndex = modeManager.configurations.firstIndex(where: { $0.id == draggedID }),
              let toIndex = modeManager.configurations.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.smooth(duration: 0.18)) {
            modeManager.moveConfigurations(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

private struct ModesTableResetDelegate: DropDelegate {
    @Binding var draggedID: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}
