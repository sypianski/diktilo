import SwiftUI
import SwiftData

struct InlineHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var expandedId: UUID?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    @State private var isPanelPresented = false
    @State private var panelMode: InlineHistoryPanelMode = .info
    @State private var panelTranscriptionId: UUID?
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?
    @State private var isViewCurrentlyVisible = false
    @State private var filter: HistoryFilter = .all
    @State private var modeFilter: String?
    @State private var isSelecting = false
    @State private var totalCount = 0
    @State private var pendingDeletion: Transcription?

    private let exportService = VoiceInkCSVExportService()
    private let pageSize = 20
    private let scanBatchSize = 60

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]

    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(after timestamp: Date? = nil, limit: Int? = nil) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = limit ?? pageSize
        return descriptor
    }

    private var allSelected: Bool {
        !displayedTranscriptions.isEmpty && displayedTranscriptions.allSatisfy { selectedTranscriptions.contains($0) }
    }

    private var panelTranscription: Transcription? {
        guard let id = panelTranscriptionId else { return nil }
        return displayedTranscriptions.first { $0.id == id }
    }

    private func openPanel(mode: InlineHistoryPanelMode, transcriptionID: UUID? = nil) {
        panelMode = mode
        panelTranscriptionId = transcriptionID

        isPanelPresented = true
    }

    private func closePanel() {
        isPanelPresented = false
        panelMode = .info
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            topBar
            filterChips
            Divider()

            if displayedTranscriptions.isEmpty && !isLoading {
                emptyStateView
            } else {
                cardListView
            }

            if !selectedTranscriptions.isEmpty {
                Divider()
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTranscriptions.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sidePanel(isPresented: .init(
            get: { isPanelPresented },
            set: { newValue in
                if !newValue { closePanel() }
            }
        )) {
            panelContent
        }
        .alert("Delete this entry?", isPresented: .init(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let transcription = pendingDeletion {
                    delete([transcription])
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(localized: "This action cannot be undone. Are you sure you want to delete \(selectedTranscriptions.count) items?"))
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task { await loadInitialContent() }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in reload() }
        .onChange(of: filter) { _, _ in reload() }
        .onChange(of: modeFilter) { _, _ in reload() }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { selectedTranscriptions.removeAll() }
        }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionDeleted)) { _ in
            // Deletions may come from the other history surface (tab vs. window) or
            // auto-cleanup, so drop references to models that may no longer exist.
            selectedTranscriptions.removeAll()
            Task {
                await loadInitialContent()
                let loadedIds = Set(displayedTranscriptions.map(\.id))
                if let id = expandedId, !loadedIds.contains(id) {
                    expandedId = nil
                }
                if let id = panelTranscriptionId, !loadedIds.contains(id) {
                    panelTranscriptionId = nil
                    closePanel()
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppTheme.Surface.card)
            )
            .frame(maxWidth: .infinity)

            if !displayedTranscriptions.isEmpty {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            AppIconButton(
                systemName: "gearshape",
                help: "History settings",
                size: 30,
                iconSize: 13,
                cornerRadius: AppTheme.Radius.pill
            ) {
                openPanel(mode: .historySettings)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var header: some View {
        AppScreenHeader(title: "History") {
            Text(entryCountText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppTheme.Text.secondary)
        }
    }

    private var entryCountText: String {
        String(format: String(localized: "%lld entries"), Int64(totalCount))
    }

    /// Filters come from fields an entry already has: mode, a kept recording, an enhanced text.
    private var filterChips: some View {
        HStack(spacing: 8) {
            chip("All", isOn: filter == .all && modeFilter == nil) {
                filter = .all
                modeFilter = nil
            }

            Menu {
                Button("All") { modeFilter = nil }
                Divider()
                ForEach(modeNames, id: \.self) { name in
                    Button(name) { modeFilter = name }
                }
            } label: {
                chipLabel(
                    modeFilter ?? String(localized: "Mode"),
                    isOn: modeFilter != nil,
                    showsChevron: true
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            chip("With Recording", isOn: filter == .withAudio) {
                filter = filter == .withAudio ? .all : .withAudio
            }

            chip("Enhanced", isOn: filter == .enhanced) {
                filter = filter == .enhanced ? .all : .enhanced
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var modeNames: [String] {
        OutputProfileManager.shared.configurations.map(\.name)
    }

    private func chip(_ title: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title, isOn: isOn, showsChevron: false)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ title: LocalizedStringKey, isOn: Bool, showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if showsChevron {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(isOn ? AppTheme.Text.primary : AppTheme.Text.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(isOn ? AppTheme.Selection.fill : AppTheme.Surface.controlActive))
    }

    private func chipLabel(_ title: String, isOn: Bool, showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if showsChevron {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(isOn ? AppTheme.Text.primary : AppTheme.Text.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(isOn ? AppTheme.Selection.fill : AppTheme.Surface.controlActive))
    }

    private func reload() {
        Task {
            await resetPagination()
            await loadInitialContent()
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text(String(format: String(localized: "%lld selected"), Int64(selectedTranscriptions.count)))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                openPanel(mode: .analysis)
            }) {
                Label("Analyze", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: {
                exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: { showDeleteConfirmation = true }) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.Status.error.opacity(0.80))

            Divider()
                .frame(height: 16)

            if allSelected {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Button("Select All") {
                    Task { await selectAllTranscriptions() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            AppTheme.Surface.window
                .shadow(color: Color.black.opacity(0.1), radius: 3, y: -2)
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "Your transcription history will appear here" : "Try a different search term")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card List

    private var cardListView: some View {
        Form {
            ForEach(dayGroups, id: \.day) { group in
                Section {
                    ForEach(group.items) { transcription in
                        HistoryCardRow(
                            transcription: transcription,
                            isExpanded: expandedId == transcription.id,
                            isSelecting: isSelecting,
                            isChecked: selectedTranscriptions.contains(transcription),
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedId = expandedId == transcription.id ? nil : transcription.id
                                }
                            },
                            onToggleCheck: { toggleSelection(transcription) },
                            onShowInfo: {
                                openPanel(mode: .info, transcriptionID: transcription.id)
                            },
                            onDelete: { pendingDeletion = transcription }
                        )
                        .onAppear {
                            if transcription.id == displayedTranscriptions.last?.id, hasMoreContent {
                                Task { await loadMoreContent() }
                            }
                        }
                    }
                } header: {
                    Text(dayTitle(group.day))
                }
            }

            Section {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text(shownCountText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var shownCountText: String {
        let isUnfiltered = filter == .all && modeFilter == nil && searchText.isEmpty
        return isUnfiltered
            ? String(format: String(localized: "Shown %lld of %lld"), Int64(displayedTranscriptions.count), Int64(totalCount))
            : String(format: String(localized: "Shown %lld"), Int64(displayedTranscriptions.count))
    }

    private var dayGroups: [(day: Date, items: [Transcription])] {
        var groups: [(day: Date, items: [Transcription])] = []
        let calendar = Calendar.current
        for transcription in displayedTranscriptions {
            let day = calendar.startOfDay(for: transcription.timestamp)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(transcription)
            } else {
                groups.append((day: day, items: [transcription]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        return sameYear
            ? day.formatted(.dateTime.day().month(.wide))
            : day.formatted(.dateTime.day().month(.wide).year())
    }

    // MARK: - Side Panel

    @ViewBuilder
    private var panelContent: some View {
        switch panelMode {
        case .info:
            infoPanelContent
        case .analysis:
            PerformanceAnalysisPanelView(
                transcriptions: Array(selectedTranscriptions),
                onClose: {
                    closePanel()
                }
            )
            .id(selectedTranscriptions.count)
        case .historySettings:
            HistorySettingsPanel(onClose: closePanel)
        }
    }

    private var infoPanelContent: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Info", onClose: closePanel)

            if let transcription = panelTranscription {
                TranscriptionInfoPanel(transcription: transcription)
                    .id(transcription.id)
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Data Loading

    private func matchesFilters(_ transcription: Transcription) -> Bool {
        switch filter {
        case .all:
            break
        case .withAudio:
            guard transcription.audioFileURL != nil else { return false }
        case .enhanced:
            guard let enhanced = transcription.enhancedText,
                  !enhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }

        if let modeFilter, transcription.modeName != modeFilter {
            return false
        }

        return true
    }

    /// One page of entries that pass the filters. Filters run in memory, so
    /// scan in batches until the page is full or the history ends.
    private func fetchPage(after timestamp: Date?) throws -> (items: [Transcription], hasMore: Bool) {
        var collected: [Transcription] = []
        var cursor = timestamp
        var exhausted = false

        while collected.count <= pageSize && !exhausted {
            let batch = try modelContext.fetch(cursorQueryDescriptor(after: cursor, limit: scanBatchSize))
            if batch.count < scanBatchSize { exhausted = true }
            collected.append(contentsOf: batch.filter(matchesFilters))
            cursor = batch.last?.timestamp
        }

        return (Array(collected.prefix(pageSize)), collected.count > pageSize || !exhausted)
    }

    @MainActor
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lastTimestamp = nil
            totalCount = (try? modelContext.fetchCount(FetchDescriptor<Transcription>())) ?? 0
            let page = try fetchPage(after: nil)
            displayedTranscriptions = page.items
            lastTimestamp = page.items.last?.timestamp
            hasMoreContent = page.hasMore && !page.items.isEmpty
        } catch {
            print("Error loading transcriptions: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try fetchPage(after: lastTimestamp)
            displayedTranscriptions.append(contentsOf: page.items)
            self.lastTimestamp = page.items.last?.timestamp
            hasMoreContent = page.hasMore && !page.items.isEmpty
        } catch {
            print("Error loading more transcriptions: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedTranscriptions = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    // MARK: - Selection & Deletion

    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }

    private func performDeletion(for transcription: Transcription) {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        if expandedId == transcription.id {
            expandedId = nil
        }
        if panelTranscriptionId == transcription.id {
            panelTranscriptionId = nil
            closePanel()
        }

        selectedTranscriptions.remove(transcription)
        modelContext.delete(transcription)
    }

    private func deleteSelectedTranscriptions() {
        delete(Array(selectedTranscriptions))
    }

    private func delete(_ transcriptions: [Transcription]) {
        for transcription in transcriptions {
            performDeletion(for: transcription)
        }
        selectedTranscriptions.removeAll()

        Task {
            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            } catch {
                print("Error saving deletion: \(error.localizedDescription)")
                await loadInitialContent()
            }
        }
    }

    private func selectAllTranscriptions() async {
        do {
            var allDescriptor = FetchDescriptor<Transcription>()

            if !searchText.isEmpty {
                allDescriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
                }
            }

            allDescriptor.propertiesToFetch = [\.id]
            let allTranscriptions = try modelContext.fetch(allDescriptor)
            let visibleIds = Set(displayedTranscriptions.map { $0.id })

            await MainActor.run {
                selectedTranscriptions = Set(displayedTranscriptions)

                for transcription in allTranscriptions {
                    if !visibleIds.contains(transcription.id) {
                        selectedTranscriptions.insert(transcription)
                    }
                }
            }
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }
}

private enum HistoryFilter {
    case all
    case withAudio
    case enhanced
}

private enum InlineHistoryPanelMode {
    case info
    case analysis
    case historySettings
}

// MARK: - History Card Row

private struct HistoryCardRow: View {
    let transcription: Transcription
    let isExpanded: Bool
    let isSelecting: Bool
    let isChecked: Bool
    let onToggleExpand: () -> Void
    let onToggleCheck: () -> Void
    let onShowInfo: () -> Void
    let onDelete: () -> Void

    @State private var selectedTab: TranscriptionTab = .original

    private var isCanceled: Bool {
        transcription.transcriptionStatus == TranscriptionStatus.canceled.rawValue
    }

    private var displayText: String {
        switch selectedTab {
        case .original:
            return transcription.text
        case .enhanced:
            return transcription.enhancedText ?? ""
        }
    }

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if isSelecting {
                    Toggle("", isOn: Binding(
                        get: { isChecked },
                        set: { _ in onToggleCheck() }
                    ))
                    .toggleStyle(CircularCheckboxStyle())
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 4) {
                    metaLine

                    if isCanceled {
                        Label("The transcription was canceled.", systemImage: "nosign")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else if !isExpanded {
                        Text(transcription.enhancedText ?? transcription.text)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                if !isCanceled {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isCanceled { onToggleExpand() } }

            if isExpanded && !isCanceled {
                expandedContent
                    .padding(.top, 10)
            }
        }
        .opacity(isCanceled ? 0.6 : 1)
    }

    /// Time, mode chip, length, and icons for "has a recording" / "was enhanced".
    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(transcription.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            if let modeName = transcription.modeName, !modeName.isEmpty {
                Text(modeName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(AppTheme.Surface.controlActive))
                    .lineLimit(1)
            }

            if transcription.duration > 0 {
                Text(transcription.duration.formatTiming())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if transcription.audioFileURL != nil {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .help("Recording kept")
            }

            if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .help("Enhanced")
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tabs
            if transcription.enhancedText != nil {
                HStack(spacing: 4) {
                    ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(LocalizedStringKey(tab.rawValue))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? AppTheme.Surface.controlActive : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            ScrollView {
                MarkdownContentView(
                    displayText,
                    fontSize: 14,
                    foregroundColor: AppTheme.Text.primary
                )
            }
            .frame(maxHeight: 350)

            detailsLine

            actionBar

            if hasAudioFile, let urlString = transcription.audioFileURL,
               let url = URL(string: urlString) {
                Divider()
                AudioPlayerView(url: url, transcription: transcription)
                    .padding(.vertical, 4)
            }
        }
    }

    /// Models, timings, prompt: what the Info panel listed first, now under the text.
    private var detailsLine: some View {
        let chips = detailChips
        return Group {
            if !chips.isEmpty {
                Text(chips.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailChips: [String] {
        var chips: [String] = []
        if let model = transcription.transcriptionModelName {
            if let time = transcription.transcriptionDuration {
                chips.append("\(model) \(time.formatTiming())")
            } else {
                chips.append(model)
            }
        }
        if let model = transcription.aiEnhancementModelName {
            if let time = transcription.enhancementDuration {
                chips.append("\(model) \(time.formatTiming())")
            } else {
                chips.append(model)
            }
        }
        if let prompt = transcription.promptName {
            chips.append(prompt)
        }
        return chips
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayText, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(action: onShowInfo) {
                Label("Details", systemImage: "info.circle")
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .foregroundColor(AppTheme.Status.error.opacity(0.8))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }
}

struct CircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? AppTheme.Selection.foreground : .secondary)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}
