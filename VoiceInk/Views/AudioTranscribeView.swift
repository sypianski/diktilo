import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AudioTranscribeView: View {
    /// The mode used for files is remembered separately from the active recording mode.
    private static let fileModeKey = "fileTranscriptionModeID"

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: VoiceInkEngine
    @ObservedObject private var modeManager = OutputProfileManager.shared
    @StateObject private var transcriptionManager = AudioTranscriptionManager.shared
    @State private var isDropTargeted = false
    @State private var showOutputProfilePopover = false
    @State private var selectedModeId: UUID?
    @State private var expandedItemId: UUID?

    private var selectedMode: OutputProfile? {
        modeManager.resolvedEnabledConfiguration(preferredId: selectedModeId)
    }

    private var hasListContent: Bool {
        !transcriptionManager.queue.isEmpty || !transcriptionManager.skipped.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if hasListContent {
                Divider()
                queueFormView
                Divider()
                bottomBar
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .data, .audio, .movie], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers)
            return true
        }
        .overlay {
            if isDropTargeted && hasListContent {
                dropOverlay
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileForTranscription)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                transcriptionManager.addToQueue(urls: [url])
            }
        }
        .onChange(of: transcriptionManager.lastCompletedItemId) { _, newId in
            if let newId {
                withAnimation(.easeInOut(duration: 0.3)) {
                    expandedItemId = newId
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Transcribe File")
                .font(.title3.weight(.semibold))

            Spacer()

            modePicker
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Text("The result is saved in History.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.Surface.window.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 2, dash: [8])
                            )
                            .foregroundColor(isDropTargeted ? AppTheme.Accent.primary : .gray.opacity(0.5))
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDropTargeted)

                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundColor(isDropTargeted ? AppTheme.Accent.primary : .gray)

                    Text("Drop audio or video files here")
                        .font(.headline)

                    Text("or")
                        .foregroundColor(.secondary)

                    Button("Choose Files") {
                        selectFiles()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(32)
            }
            .frame(maxWidth: 480, maxHeight: 200)

            Text("Supports WAV, MP3, M4A, AIFF, MP4, MOV, AAC, FLAC, CAF, AMR, OGG, OPUS, 3GP")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 12)

            Spacer()
        }
        .padding(.bottom)
    }

    // MARK: - Queue Form View

    private var queueFormView: some View {
        Form {
            ForEach(transcriptionManager.queue) { item in
                Section {
                    AudioFileRow(
                        item: item,
                        isExpanded: expandedItemId == item.id,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedItemId = expandedItemId == item.id ? nil : item.id
                            }
                        },
                        onRemove: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                transcriptionManager.removeFromQueue(id: item.id)
                                if expandedItemId == item.id { expandedItemId = nil }
                            }
                        },
                        onRetry: {
                            transcriptionManager.retryItem(id: item.id)
                            startProcessing()
                        },
                        onShowInHistory: { navigate(to: .history) },
                        onChooseModel: { navigate(to: .models) }
                    )
                }
            }

            ForEach(transcriptionManager.skipped) { file in
                Section {
                    SkippedFileRow(file: file) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            transcriptionManager.removeSkipped(id: file.id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        let queued = transcriptionManager.queue.count
        let pending = transcriptionManager.pendingCount

        return HStack(spacing: 10) {
            Text("\(queued) files")
                .font(.subheadline)
                .foregroundColor(.secondary)

            barButton(title: "Add", systemImage: "plus") {
                selectFiles()
            }
            .help("Add files")

            if transcriptionManager.hasFinishedItems || !transcriptionManager.skipped.isEmpty {
                barButton(title: "Clear finished", systemImage: "xmark.bin") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        transcriptionManager.clearFinished()
                        transcriptionManager.skipped.removeAll()
                        expandedItemId = nil
                    }
                }
                .help("Remove finished and skipped files; waiting ones stay")
            } else if !transcriptionManager.isProcessingQueue {
                barButton(title: "Clear", systemImage: "xmark.bin") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        transcriptionManager.clearAll()
                        expandedItemId = nil
                    }
                }
                .help("Clear all items")
            }

            Spacer()

            if transcriptionManager.isProcessingQueue {
                Button {
                    transcriptionManager.cancelProcessing()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text("Cancel")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.Status.error)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(AppTheme.Status.error.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .help("Cancel transcription")
            } else if pending > 0 {
                Button {
                    startProcessing()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text("Start (\(pending) files)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(AppTheme.Accent.primary)
                            .shadow(color: AppTheme.Accent.shadow, radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedMode == nil)
                .opacity(selectedMode == nil ? 0.5 : 1.0)
                .help(selectedMode == nil ? "Select an enabled mode to start" : "Start transcription")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func barButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(AppTheme.Surface.controlActive)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode

    private var modePicker: some View {
        HStack(spacing: 6) {
            Text("Mode for files")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if modeManager.enabledConfigurations.isEmpty {
                Text("None")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else if let selectedMode {
                Button {
                    showOutputProfilePopover.toggle()
                } label: {
                    HStack(spacing: 6) {
                        ModeIconView(icon: selectedMode.icon, size: selectedMode.icon.kind == .emoji ? 13 : 11)
                            .frame(width: 16)
                        Text(selectedMode.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: 160, alignment: .leading)
                    .background(
                        Capsule()
                            .fill(AppTheme.Surface.subtle)
                    )
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.Accent.fillSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOutputProfilePopover, arrowEdge: .bottom) {
                    OutputProfilePopover(selectedModeId: selectedMode.id, detail: modeDetail) { mode in
                        selectMode(mode)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            restoreSavedMode()
            syncSelectedMode()
        }
        .onChange(of: modeManager.enabledConfigurations.map(\.id)) { _, _ in
            syncSelectedMode()
        }
    }

    /// Second line under a mode's name: the speech model and whether text improvement runs.
    private func modeDetail(_ mode: OutputProfile) -> String? {
        let model = engine.transcriptionModelManager.usableModelsInChainOrder().first?.displayName
        let improvement = mode.isAIEnhancementEnabled
            ? String(localized: "Text improvement")
            : String(localized: "No text improvement")
        return [model, improvement].compactMap { $0 }.joined(separator: " · ")
    }

    private func restoreSavedMode() {
        guard selectedModeId == nil,
              let raw = UserDefaults.standard.string(forKey: Self.fileModeKey),
              let id = UUID(uuidString: raw) else { return }
        selectedModeId = id
    }

    private func syncSelectedMode() {
        selectedModeId = modeManager.resolvedEnabledConfigurationId(preferredId: selectedModeId)
    }

    /// Picking a mode here only affects file transcription; the recording mode is untouched.
    private func selectMode(_ mode: OutputProfile) {
        selectedModeId = mode.id
        UserDefaults.standard.set(mode.id.uuidString, forKey: Self.fileModeKey)
        showOutputProfilePopover = false
    }

    private func startProcessing() {
        guard let selectedMode else { return }
        transcriptionManager.startProcessing(modelContext: modelContext, engine: engine, mode: selectedMode)
    }

    private func navigate(to view: ViewType) {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": view.rawValue]
        )
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(AppTheme.Accent.primary, style: StrokeStyle(lineWidth: 2, dash: [8]))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.Accent.fillSubtle)
            )
            .overlay {
                Text("Drop to add files")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppTheme.Accent.text)
            }
            .padding(16)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    // MARK: - File Handling

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie]

        if panel.runModal() == .OK {
            transcriptionManager.addToQueue(urls: panel.urls)
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        let typeIdentifiers = [
            UTType.fileURL.identifier,
            UTType.audio.identifier,
            UTType.movie.identifier,
            UTType.data.identifier,
            "public.file-url"
        ]

        for provider in providers {
            for typeIdentifier in typeIdentifiers {
                if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                        if let error = error {
                            print("Error loading dropped file: \(error)")
                            return
                        }

                        var fileURL: URL?

                        if let url = item as? URL {
                            fileURL = url
                        } else if let data = item as? Data {
                            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                                fileURL = url
                            } else if let urlString = String(data: data, encoding: .utf8),
                                      let url = URL(string: urlString) {
                                fileURL = url
                            }
                        } else if let urlString = item as? String {
                            fileURL = URL(string: urlString)
                        }

                        if let finalURL = fileURL {
                            DispatchQueue.main.async {
                                self.transcriptionManager.addToQueue(urls: [finalURL])
                            }
                        }
                    }
                    break
                }
            }
        }
    }
}
