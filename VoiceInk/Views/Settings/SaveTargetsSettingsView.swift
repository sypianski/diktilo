import SwiftUI

// MARK: - SaveTargetsSettingsView

struct SaveTargetsSettingsView: View {
    @ObservedObject private var manager = SaveTargetManager.shared
    @State private var isAddingNew = false
    @State private var editingTarget: SaveTargetConfig?
    @State private var deletionTarget: SaveTargetConfig?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if manager.targets.isEmpty {
                emptyState
            } else {
                targetList
            }
        }
        .sheet(isPresented: $isAddingNew) {
            SaveTargetEditorView(existingTarget: nil) { newTarget in
                manager.add(newTarget)
            }
        }
        .sheet(item: $editingTarget) { target in
            SaveTargetEditorView(existingTarget: target) { updated in
                manager.update(updated)
            }
        }
        .confirmationDialog(
            "Delete Save Target?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let t = deletionTarget {
                    manager.delete(with: t.id)
                }
                deletionTarget = nil
            }
            Button("Cancel", role: .cancel) {
                deletionTarget = nil
            }
        } message: {
            if let t = deletionTarget {
                Text(String(format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."), t.name))
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Custom Target…") {
                        isAddingNew = true
                    }
                    Button("Notaro") {
                        addNotaroPreset()
                    }
                } label: {
                    Label("Add Save Target", systemImage: "plus")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No Save Targets")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Add a target to save transcripts to a file, URL scheme, shell command, or Sako.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            HStack(spacing: 12) {
                Button("Add Save Target") {
                    isAddingNew = true
                }
                .buttonStyle(.borderedProminent)

                Button("Add Notaro") {
                    addNotaroPreset()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addNotaroPreset() {
        let preset = SaveTargetConfig.notaroPreset()
        manager.add(preset)
        FinishDestinationBindings.assignDefaultNotaroShortcut(targetID: preset.id)
    }

    private var targetList: some View {
        List {
            ForEach(manager.targets) { target in
                SaveTargetRow(target: target) {
                    editingTarget = target
                } onDelete: {
                    deletionTarget = target
                    showDeleteConfirmation = true
                }
            }
        }
    }
}

// MARK: - SaveTargetRow

private struct SaveTargetRow: View {
    let target: SaveTargetConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .fontWeight(.medium)
                Text(target.strategyDisplayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Finish shortcut")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ShortcutRecorder(action: .finishWithSaveTarget(target.id))
                    .controlSize(.small)
            }

            Button("Edit") { onEdit() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Delete", role: .destructive) { onDelete() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - SaveTargetEditorView

struct SaveTargetEditorView: View {
    let existingTarget: SaveTargetConfig?
    let onSave: (SaveTargetConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    // Editable fields
    @State private var name: String
    @State private var icon: String
    @State private var strategyKind: StrategyKind

    // File strategy fields
    @State private var directoryPath: String
    @State private var filenameTemplate: String
    @State private var fileFormat: SaveTargetFileFormat
    @State private var appendToExisting: Bool

    // URL scheme fields
    @State private var urlTemplate: String
    @State private var urlActivates: Bool

    // Shell command fields
    @State private var shellCommand: String

    enum StrategyKind: String, CaseIterable, Identifiable {
        case file
        case urlScheme
        case shellCommand
        case sako

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .file: return String(localized: "File")
            case .urlScheme: return String(localized: "URL Scheme")
            case .shellCommand: return String(localized: "Shell Command")
            case .sako: return String(localized: "Sako")
            }
        }
    }

    init(existingTarget: SaveTargetConfig?, onSave: @escaping (SaveTargetConfig) -> Void) {
        self.existingTarget = existingTarget
        self.onSave = onSave

        let t = existingTarget
        _name = State(initialValue: t?.name ?? "")
        _icon = State(initialValue: t?.icon ?? "square.and.arrow.down")

        switch t?.strategy {
        case .file(let fs):
            _strategyKind = State(initialValue: .file)
            _directoryPath = State(initialValue: fs.directoryPath)
            _filenameTemplate = State(initialValue: fs.filenameTemplate)
            _fileFormat = State(initialValue: fs.format)
            _appendToExisting = State(initialValue: fs.appendToExisting)
            _urlTemplate = State(initialValue: "")
            _urlActivates = State(initialValue: true)
            _shellCommand = State(initialValue: "")
        case .urlScheme(let template, let activates):
            _strategyKind = State(initialValue: .urlScheme)
            _directoryPath = State(initialValue: "~/Documents")
            _filenameTemplate = State(initialValue: "{date}-{slug}")
            _fileFormat = State(initialValue: .markdown)
            _appendToExisting = State(initialValue: false)
            _urlTemplate = State(initialValue: template)
            _urlActivates = State(initialValue: activates)
            _shellCommand = State(initialValue: "")
        case .shellCommand(let cmd):
            _strategyKind = State(initialValue: .shellCommand)
            _directoryPath = State(initialValue: "~/Documents")
            _filenameTemplate = State(initialValue: "{date}-{slug}")
            _fileFormat = State(initialValue: .markdown)
            _appendToExisting = State(initialValue: false)
            _urlTemplate = State(initialValue: "")
            _urlActivates = State(initialValue: true)
            _shellCommand = State(initialValue: cmd)
        case .sako, nil:
            _strategyKind = State(initialValue: t?.strategy == nil ? .file : .sako)
            _directoryPath = State(initialValue: "~/Documents")
            _filenameTemplate = State(initialValue: "{date}-{slug}")
            _fileFormat = State(initialValue: .markdown)
            _appendToExisting = State(initialValue: false)
            _urlTemplate = State(initialValue: "")
            _urlActivates = State(initialValue: true)
            _shellCommand = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $name)

                    LabeledContent("Icon") {
                        HStack {
                            Image(systemName: icon.isEmpty ? "questionmark" : icon)
                                .frame(width: 20)
                            TextField("SF Symbol name", text: $icon)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 180)
                        }
                    }
                }

                Section("Strategy") {
                    Picker("Type", selection: $strategyKind) {
                        ForEach(StrategyKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    strategyFields
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingTarget == nil ? String(localized: "Add Save Target") : String(localized: "Edit Save Target"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 400)
    }

    @ViewBuilder
    private var strategyFields: some View {
        switch strategyKind {
        case .file:
            fileStrategyFields
        case .urlScheme:
            urlSchemeFields
        case .shellCommand:
            shellCommandFields
        case .sako:
            LabeledContent("Sako") {
                Text("Text will be sent to your Sako inbox via the CLI or JSONL fallback.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var fileStrategyFields: some View {
        Group {
            TextField("Directory", text: $directoryPath, prompt: Text("~/Documents"))
            TextField("Filename Template", text: $filenameTemplate, prompt: Text("{date}-{slug}"))
                .help("Tokens: {date} {time} {datetime} {slug}")
            Picker("Format", selection: $fileFormat) {
                ForEach(SaveTargetFileFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            Toggle("Append to existing file", isOn: $appendToExisting)
        }
    }

    private var urlSchemeFields: some View {
        Group {
            TextField("URL Template", text: $urlTemplate, prompt: Text("notaro://add?text={{text}}&source=diktilo"))
                .help("Use {{text}} or {text} as a placeholder for the transcript.")
            Toggle(String(localized: "Open target app"), isOn: $urlActivates)
            Text("When off, the text is delivered silently in the background.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var shellCommandFields: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $shellCommand)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("The transcript is sent on stdin and exposed as VOICEINK_TRANSCRIPT.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func save() {
        let strategy: SaveTargetConfig.Strategy
        switch strategyKind {
        case .file:
            strategy = .file(SaveTargetConfig.FileStrategy(
                directoryPath: directoryPath.isEmpty ? "~/Documents" : directoryPath,
                filenameTemplate: filenameTemplate.isEmpty ? "{date}-{slug}" : filenameTemplate,
                format: fileFormat,
                appendToExisting: appendToExisting
            ))
        case .urlScheme:
            strategy = .urlScheme(template: urlTemplate, activates: urlActivates)
        case .shellCommand:
            strategy = .shellCommand(command: shellCommand)
        case .sako:
            strategy = .sako
        }

        let config = SaveTargetConfig(
            id: existingTarget?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "square.and.arrow.down" : icon,
            strategy: strategy
        )
        onSave(config)
    }
}
