import SwiftUI

struct OutputProfileFormView: View {
    let mode: ConfigurationMode
    let modeManager: OutputProfileManager
    @Binding var draft: OutputProfileDraft
    @Binding var validationErrors: [ModeValidationError]
    @Binding var showValidationAlert: Bool
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let openPromptEditor: (PromptEditorView.Mode) -> Void

    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var modeWarmupStore: OutputProfileFormWarmupStore
    @FocusState private var isNameFieldFocused: Bool

    @State private var isShowingIconPicker = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isContextAwarenessExpanded = false

    private var warmupSnapshot: ModeFormWarmupSnapshot {
        modeWarmupStore.snapshot
    }

    private var selectedPrompt: CustomPrompt? {
        guard let selectedPromptId = draft.selectedPromptId else { return nil }
        return warmupSnapshot.prompts.first { $0.id == selectedPromptId }
    }

    private var aiProviderOptions: [AIProvider] {
        warmupSnapshot.connectedAIProviders
    }

    private var configuredSelectedAIProvider: AIProvider? {
        let selectedProvider: AIProvider?
        if let providerName = draft.selectedAIProvider {
            selectedProvider = AIProvider(rawValue: providerName)
        } else {
            selectedProvider = aiProviderOptions.first
        }

        guard let selectedProvider,
              selectedProvider.supportsEnhancement,
              aiProviderOptions.contains(selectedProvider) else { return nil }

        return selectedProvider
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            formContent

            footer
        }
        .onAppear {
            applyOutputRules()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
        .onChange(of: draft.isAIEnhancementEnabled) { _, _ in
            applyOutputRules()
        }
        .onChange(of: draft.selectedPromptId) { _, _ in
            applyOutputRules()
        }
        .onChange(of: draft.selectedAIProvider) { _, _ in
            applyOutputRules()
        }
        .onChange(of: draft.selectedAIModel) { _, _ in
            applyOutputRules()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                isShowingIconPicker.toggle()
            } label: {
                ModeIconView(icon: draft.icon, size: draft.icon.kind == .emoji ? 22 : 18)
                    .frame(width: 36, height: 36)
                    .background(
                        AppCardBackground(isSelected: false, cornerRadius: 18)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingIconPicker, arrowEdge: .bottom) {
                ModeIconPickerView(
                    selectedIcon: $draft.icon,
                    isPresented: $isShowingIconPicker
                )
            }

            TextField("Profile name", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .focused($isNameFieldFocused)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(AppTheme.Surface.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var formContent: some View {
        Form {
            ModeTriggerSection(
                appConfigs: $draft.appConfigs,
                websiteConfigs: $draft.websiteConfigs,
                triggerGroups: $draft.triggerGroups,
                triggerWords: $draft.triggerWords,
                profileId: draft.id,
                cleanURL: modeManager.cleanURL
            )
            aiEnhancementSection
            finishSection
            advancedSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete Profile?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if case .edit = mode {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(String(format: String(localized: "Are you sure you want to delete '%@'? This action cannot be undone."), draft.name))
        }
        .modeValidationAlert(errors: validationErrors, isPresented: $showValidationAlert)
    }

    private var aiEnhancementSection: some View {
        Section("AI Enhancement") {
            Toggle("AI Enhancement", isOn: $draft.isAIEnhancementEnabled)
                .onChange(of: draft.isAIEnhancementEnabled) { _, newValue in
                    if newValue {
                        if configuredSelectedAIProvider == nil {
                            draft.selectedAIProvider = aiProviderOptions.first?.rawValue
                            draft.selectedAIModel = nil
                        }
                        if draft.selectedAIModel == nil,
                           let provider = configuredSelectedAIProvider,
                           provider != .localCLI {
                            draft.selectedAIModel = warmupSnapshot.selectedModel(for: provider)
                        }
                        if draft.selectedPromptId == nil {
                            draft.selectedPromptId = warmupSnapshot.firstPromptId
                        }
                        if configuredSelectedAIProvider == .ollama {
                            aiService.refreshOllamaAvailabilityInBackground()
                        }
                    }
                }

            let providerBinding = Binding<AIProvider>(
                get: {
                    configuredSelectedAIProvider ?? aiProviderOptions.first ?? .gemini
                },
                set: { newValue in
                    draft.selectedAIProvider = newValue.rawValue
                    draft.selectedAIModel = nil
                }
            )

            if draft.isAIEnhancementEnabled {
                let providerOptions = aiProviderOptions

                if providerOptions.isEmpty {
                    LabeledContent("AI Provider") {
                        Text("No providers connected")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                } else {
                    Picker("AI Provider", selection: providerBinding) {
                        ForEach(providerOptions, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .onChange(of: draft.selectedAIProvider) { _, newValue in
                        if let provider = newValue.flatMap({ AIProvider(rawValue: $0) }) {
                            switch provider {
                            case .localCLI:
                                draft.selectedAIModel = nil
                            case .ollama:
                                if draft.selectedAIModel == nil || draft.selectedAIModel?.isEmpty == true {
                                    draft.selectedAIModel = warmupSnapshot.selectedModel(for: provider)
                                }
                                aiService.refreshOllamaAvailabilityInBackground()
                            default:
                                draft.selectedAIModel = provider.defaultModel
                            }
                        }
                    }
                }

                if let provider = configuredSelectedAIProvider {
                    aiModelPicker(for: provider)
                    promptPicker
                    contextAwarenessRow
                }
            }
        }
    }

    @ViewBuilder
    private func aiModelPicker(for provider: AIProvider) -> some View {
        if provider == .localCLI {
            LabeledContent("AI Model") {
                Text("Default")
                    .foregroundColor(.secondary)
            }
            .onAppear {
                draft.selectedAIModel = nil
            }
        } else {
            let models = aiModelOptions(for: provider)
            if models.isEmpty {
                LabeledContent("AI Model") {
                    Text(provider == .openRouter ? LocalizedStringKey("No models loaded") : LocalizedStringKey("No models available"))
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                let modelBinding = Binding<String>(
                    get: {
                        if let model = draft.selectedAIModel, !model.isEmpty { return model }
                        return warmupSnapshot.selectedModel(for: provider)
                    },
                    set: { newModelValue in
                        draft.selectedAIModel = newModelValue
                    }
                )

                Picker("AI Model", selection: modelBinding) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                if provider == .openRouter {
                    Button("Refresh Models") {
                        Task { await aiService.fetchOpenRouterModels() }
                    }
                    .help("Refresh models")
                }
            }
        }
    }

    private func aiModelOptions(for provider: AIProvider) -> [String] {
        var models = warmupSnapshot.availableModels(for: provider)

        if let selectedModel = draft.selectedAIModel,
           !selectedModel.isEmpty,
           !models.contains(selectedModel) {
            models.insert(selectedModel, at: 0)
        }

        return models
    }

    private var promptPicker: some View {
        HStack(spacing: 8) {
            Text("Prompt")

            Spacer(minLength: 12)

            if warmupSnapshot.prompts.isEmpty {
                Text("No prompts available")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Picker("", selection: $draft.selectedPromptId) {
                    ForEach(warmupSnapshot.prompts) { prompt in
                        Text(prompt.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(prompt.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if let selectedPrompt {
                Button {
                    openPromptEditor(.edit(selectedPrompt))
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit prompt")
            }

            AddIconButton(helpText: "Add prompt") {
                openPromptEditor(.add)
            }
        }
    }

    private var contextAwarenessRow: some View {
        ExpandableSettingsRow(
            title: "Context Awareness",
            isExpanded: $isContextAwarenessExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                contextToggles
            }
        }
    }

    private var contextToggles: some View {
        Group {
            Toggle(isOn: $draft.useSelectedTextContext) {
                HStack(spacing: 4) {
                    Text("Selected Text")
                    InfoTip("Use selected text from the active app as context for this profile.")
                }
            }

            Toggle(isOn: $draft.useClipboardContext) {
                HStack(spacing: 4) {
                    Text("Clipboard")
                    InfoTip("Use clipboard text as context for this profile.")
                }
            }

            Toggle(isOn: $draft.useScreenCapture) {
                HStack(spacing: 4) {
                    Text("Screen")
                    InfoTip("Use captured on-screen text as context for this profile.")
                }
            }
        }
    }

    private var outputChoices: [OutputMode] {
        OutputMode.choices(canRespond: canRespond)
    }

    private var canRespond: Bool {
        draft.isAIEnhancementEnabled &&
            selectedPrompt != nil &&
            configuredSelectedAIProvider != nil
    }

    private func applyOutputRules() {
        draft.applyOutputRules(canRespond: canRespond)
    }

    private var finishSection: some View {
        Section {
            LabeledContent("Finish Shortcut") {
                ShortcutRecorder(action: .profile(draft.id))
                    .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 4) {
                Text("Press during recording to finish and deliver via")
                    .foregroundColor(.secondary)
                Text(draft.outputMode.displayName)
                    .foregroundColor(.primary)
                    .fontWeight(.medium)
                Text(".")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .font(.system(size: 11))

            if draft.outputMode.usesPasteOptions {
                pasteOverridesGroup
            }
        } header: {
            Text("Finish")
        }
    }

    @ViewBuilder
    private var pasteOverridesGroup: some View {
        let customPasteBinding = Binding<Bool>(
            get: {
                draft.pasteMethodOverride != nil
                    || draft.restoreClipboardOverride != nil
                    || draft.clipboardRestoreDelayOverride != nil
            },
            set: { isOn in
                if !isOn {
                    draft.pasteMethodOverride = nil
                    draft.restoreClipboardOverride = nil
                    draft.clipboardRestoreDelayOverride = nil
                } else {
                    // Seed with current global values so switching on doesn't
                    // silently change behavior.
                    let globalPaste = UserDefaults.standard.string(forKey: PasteMethod.userDefaultsKey)
                        ?? PasteMethod.standard.rawValue
                    draft.pasteMethodOverride = globalPaste
                    draft.restoreClipboardOverride = UserDefaults.standard.object(forKey: "restoreClipboardAfterPaste") as? Bool ?? true
                    let globalDelay = UserDefaults.standard.object(forKey: "clipboardRestoreDelay") as? Double ?? 2.0
                    draft.clipboardRestoreDelayOverride = globalDelay
                }
            }
        )

        Toggle(isOn: customPasteBinding) {
            HStack(spacing: 4) {
                Text("Custom paste settings")
                InfoTip("Override the global paste method and clipboard-restore behavior for this mode only.")
            }
        }

        if customPasteBinding.wrappedValue {
            Picker(selection: Binding(
                get: { draft.pasteMethodOverride ?? PasteMethod.standard.rawValue },
                set: { draft.pasteMethodOverride = $0 }
            )) {
                ForEach(PasteMethod.allCases) { method in
                    Text(method.displayName).tag(method.rawValue)
                }
            } label: {
                Text("Paste Method")
            }
            .pickerStyle(.menu)

            Toggle(isOn: Binding(
                get: { draft.restoreClipboardOverride ?? true },
                set: { draft.restoreClipboardOverride = $0 }
            )) {
                Text("Keep Clipboard Content")
            }

            if (draft.restoreClipboardOverride ?? true) {
                Picker(selection: Binding(
                    get: { draft.clipboardRestoreDelayOverride ?? 2.0 },
                    set: { draft.clipboardRestoreDelayOverride = $0 }
                )) {
                    Text("250ms").tag(0.25)
                    Text("500ms").tag(0.5)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("4s").tag(4.0)
                    Text("5s").tag(5.0)
                } label: {
                    Text("Restore Delay")
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Picker("Output", selection: $draft.outputMode) {
                ForEach(outputChoices, id: \.self) { outputMode in
                    Label(outputMode.displayName, systemImage: outputMode.iconName)
                        .tag(outputMode)
                }
            }
            .onChange(of: draft.outputMode) { _, _ in
                applyOutputRules()
            }

            if draft.outputMode != .respond {
                Toggle(isOn: $draft.isDefault) {
                    HStack(spacing: 6) {
                        Text("Set as default")
                        InfoTip("Default profile is used when no specific app or website matches are found.")
                    }
                }
            }

            if draft.outputMode.usesPasteOptions {
                Picker(selection: $draft.autoSendKey) {
                    ForEach(AutoSendKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Auto Send")
                        InfoTip("Automatically presses a key combination after pasting text. Useful for chat applications or forms that use different send shortcuts.")
                    }
                }
            }

            if draft.outputMode == .customCommand {
                customCommandControls
            }

            if draft.outputMode == .saveTarget {
                saveTargetControls
            }

            if draft.outputMode == .editWindow {
                editWindowNote
            }
        }
    }

    @ViewBuilder
    private var editWindowNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Opens the transcript in your external editor app before delivery; committing there copies the edited text to the clipboard.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if !TranscriptEditManager.isExternalEditorInstalled {
                Label("No editor app installed — the transcript falls back to the clipboard.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var saveTargetControls: some View {
        let targets = SaveTargetManager.shared.targets
        if targets.isEmpty {
            LabeledContent("Save Target") {
                Text("No targets configured — add one in Settings → Save Targets.")
                    .foregroundColor(.secondary)
                    .italic()
            }
        } else {
            let targetBinding = Binding<UUID?>(
                get: { draft.saveTargetID },
                set: { draft.saveTargetID = $0 }
            )
            Picker("Save Target", selection: targetBinding) {
                Text("None").tag(UUID?.none)
                ForEach(targets) { target in
                    Label(target.name, systemImage: target.icon)
                        .tag(Optional(target.id))
                }
            }
        }
    }

    private var customCommandControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Command")
                InfoTip(LocalizedStringKey("Runs locally with your user permissions. The final transcript is sent on stdin and exposed as VOICEINK_TRANSCRIPT."))
                Spacer()
                Menu {
                    ForEach(CustomCommandTemplate.allCases) { template in
                        Button(template.displayName) {
                            draft.customCommand = template.command
                        }
                    }
                } label: {
                    Label("Template", systemImage: "doc.on.doc")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            TextEditor(text: $draft.customCommand)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.Surface.control)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.Border.control.opacity(0.4), lineWidth: 1)
                )

        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack {
                if case .edit = mode {
                    Button("Delete", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Cancel") { onDismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    onSave()
                } label: {
                    Text("Save Changes")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}
