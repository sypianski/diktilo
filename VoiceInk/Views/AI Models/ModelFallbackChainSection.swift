import SwiftUI
import UniformTypeIdentifiers

/// "Model order": the fallback chain for transcription and for AI enhancement,
/// drawn like the icon's paper tape — numbered links joined by perforation,
/// each gap saying why Diktilo moves on to the next model.
///
/// Reordering: drag a link (onDrag/onDrop works inside the screen's ScrollView,
/// unlike List.onMove which needs a fixed-height List), or use the link's
/// context menu, which also serves keyboard and VoiceOver users.
struct ModelFallbackChainSection: View {
    enum Kind: Hashable {
        case transcription
        case enhancement
    }

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var aiService: AIService
    @AppStorage("EnhancementTimeoutSeconds") private var enhancementTimeout = 7

    @State private var kind: Kind = .transcription
    @State private var transcriptionOrder: [String] = []
    @State private var enhancementLinks: [ModelFallbackChain.EnhancementLink] = []
    @State private var draggingID: String?
    @State private var isAddingModel = false
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch kind {
            case .transcription:
                transcriptionChain
            case .enhancement:
                enhancementChain
            }

            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.card))
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ModelFallbackChain.didChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .didChangeModel)) { _ in reload() }
    }

    private func reload() {
        transcriptionOrder = ModelFallbackChain.transcriptionOrder
        enhancementLinks = ModelFallbackChain.enhancementLinks
    }

    // MARK: - Header & footer

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Model Order")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text("Diktilo starts with the first one. If a model doesn't respond or returns an error, it takes the next one on the list.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Picker("Model Order", selection: $kind) {
                Text("Transcription").tag(Kind.transcription)
                Text("AI Enhancement").tag(Kind.enhancement)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                searchText = ""
                isAddingModel = true
            } label: {
                Label("Add Fallback Model", systemImage: "plus")
            }
            .buttonStyle(.amberProminent)
            .popover(isPresented: $isAddingModel, arrowEdge: .bottom) {
                addModelPopover
            }

            Spacer(minLength: 8)

            Text("Drag to change the order")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
        }
        .padding(.top, 2)
    }

    // MARK: - Transcription chain

    private var transcriptionChain: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(transcriptionOrder.enumerated()), id: \.element) { index, name in
                let model = transcriptionModelManager.allAvailableModels.first { $0.name == name }

                ChainLinkRow(
                    rank: index + 1,
                    title: transcriptionTitle(name: name, model: model),
                    detail: transcriptionDetail(model),
                    skipReason: transcriptionSkipReason(model),
                    canRemove: transcriptionOrder.count > 1,
                    onRemove: { removeTranscription(name) },
                    onMoveUp: index > 0 ? { moveTranscription(name, by: -1) } : nil,
                    onMoveDown: index < transcriptionOrder.count - 1 ? { moveTranscription(name, by: 1) } : nil
                )
                .onDrag {
                    draggingID = name
                    return NSItemProvider(object: name as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ReorderDropDelegate(
                        targetID: name,
                        draggingID: $draggingID,
                        move: { moveTranscription($0, to: $1) },
                        commit: commitTranscriptionOrder
                    )
                )

                ChainConnector(reason: index == transcriptionOrder.count - 1
                    ? String(localized: "if none of them works")
                    : transcriptionConnectorReason(model))
            }

            ChainEnding(
                systemImage: "doc.text",
                text: "The recording stays in History and you get a notification with a Transcribe Again button."
            )
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            draggingID = nil
            commitTranscriptionOrder()
            return true
        }
    }

    private func transcriptionTitle(name: String, model: (any TranscriptionModel)?) -> Text {
        guard let model else { return Text(verbatim: name).font(.system(size: 13.5, weight: .semibold, design: .monospaced)) }
        switch model.provider {
        case .whisper, .fluidAudio, .nativeApple:
            return Text(verbatim: model.displayName).font(.system(size: 13.5, weight: .semibold))
        case .custom:
            return Text(verbatim: model.displayName).font(.system(size: 13.5, weight: .semibold, design: .monospaced))
        default:
            return Text(verbatim: model.provider.rawValue + " ").font(.system(size: 13.5, weight: .semibold))
                + Text(verbatim: model.name).font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }

    private func transcriptionDetail(_ model: (any TranscriptionModel)?) -> String {
        guard let model else { return String(localized: "This model is no longer available.") }
        switch model.provider {
        case .whisper, .fluidAudio:
            return String(localized: "On this Mac, works offline")
        case .nativeApple:
            return String(localized: "Built into macOS")
        case .custom:
            return model.supportsStreaming
                ? String(localized: "Your own server, live transcription")
                : String(localized: "Your own server")
        default:
            return model.supportsStreaming
                ? String(localized: "API key, live transcription")
                : String(localized: "API key")
        }
    }

    /// nil = ready. Otherwise why the runtime passes over this link.
    private func transcriptionSkipReason(_ model: (any TranscriptionModel)?) -> String? {
        guard let model else { return String(localized: "Not available") }
        if !transcriptionModelManager.isAvailableOnCurrentOS(model) {
            return String(localized: "Needs macOS 26")
        }
        if transcriptionModelManager.usableModels.contains(where: { $0.name == model.name }) {
            return nil
        }
        switch model.provider {
        case .whisper, .fluidAudio:
            return String(localized: "Not downloaded")
        default:
            return String(localized: "No API key")
        }
    }

    private func transcriptionConnectorReason(_ model: (any TranscriptionModel)?) -> String {
        switch model?.provider {
        case .custom:
            return String(localized: "if the server doesn't respond")
        case .whisper, .fluidAudio, .nativeApple:
            return String(localized: "if the model returns an error")
        default:
            return String(localized: "if the provider doesn't respond")
        }
    }

    private func moveTranscription(_ name: String, by offset: Int) {
        guard let from = transcriptionOrder.firstIndex(of: name) else { return }
        let to = from + offset
        guard transcriptionOrder.indices.contains(to) else { return }
        transcriptionOrder.swapAt(from, to)
        commitTranscriptionOrder()
    }

    private func moveTranscription(_ name: String, to target: String) {
        guard let from = transcriptionOrder.firstIndex(of: name),
              let to = transcriptionOrder.firstIndex(of: target) else { return }
        transcriptionOrder.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    private func removeTranscription(_ name: String) {
        transcriptionOrder.removeAll { $0 == name }
        commitTranscriptionOrder()
    }

    /// The first link is the main model, so a new first link becomes it.
    private func commitTranscriptionOrder() {
        let order = transcriptionOrder
        ModelFallbackChain.setTranscriptionOrder(order)
        if let first = order.first,
           first != transcriptionModelManager.currentTranscriptionModel?.name,
           let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == first }) {
            transcriptionModelManager.setDefaultTranscriptionModel(model)
        }
    }

    // MARK: - Enhancement chain

    private var enhancementChain: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChainLinkRow(
                rank: 1,
                title: Text("Model set in the mode").font(.system(size: 13.5, weight: .semibold)),
                detail: modeModelDetail,
                skipReason: nil,
                trailingNote: String(localized: "always first")
            )

            ChainConnector(reason: enhancementLinks.isEmpty
                ? String(localized: "if none of them works")
                : String(format: String(localized: "if it doesn't answer within %lld s or returns an error"), Int64(enhancementTimeout)))

            ForEach(Array(enhancementLinks.enumerated()), id: \.element.id) { index, link in
                ChainLinkRow(
                    rank: index + 2,
                    title: enhancementTitle(link),
                    detail: enhancementDetail(link),
                    skipReason: enhancementSkipReason(link),
                    canRemove: true,
                    onRemove: { removeEnhancement(link) },
                    onMoveUp: index > 0 ? { moveEnhancement(link, by: -1) } : nil,
                    onMoveDown: index < enhancementLinks.count - 1 ? { moveEnhancement(link, by: 1) } : nil
                )
                .onDrag {
                    draggingID = link.id
                    return NSItemProvider(object: link.id as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ReorderDropDelegate(
                        targetID: link.id,
                        draggingID: $draggingID,
                        move: { moveEnhancement($0, to: $1) },
                        commit: commitEnhancementLinks
                    )
                )

                ChainConnector(reason: index == enhancementLinks.count - 1
                    ? String(localized: "if none of them works")
                    : String(localized: "if this one fails too"))
            }

            ChainEnding(
                systemImage: "list.clipboard",
                text: "Diktilo pastes the text without enhancement and shows which models failed."
            )
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            draggingID = nil
            commitEnhancementLinks()
            return true
        }
    }

    private var modeModelDetail: String {
        guard let mode = OutputProfileManager.shared.currentEffectiveConfiguration,
              mode.isAIEnhancementEnabled,
              let provider = mode.selectedAIProvider, !provider.isEmpty else {
            return String(localized: "Each mode can have its own.")
        }
        let model = [provider, mode.selectedAIModel].compactMap { $0 }.joined(separator: " ")
        return String(format: String(localized: "Each mode can have its own; %1$@ uses %2$@."), mode.name, model)
    }

    private func enhancementTitle(_ link: ModelFallbackChain.EnhancementLink) -> Text {
        let provider = Text(verbatim: link.provider).font(.system(size: 13.5, weight: .semibold))
        guard let model = link.model, !model.isEmpty else { return provider }
        return provider + Text(verbatim: " ") + Text(verbatim: model).font(.system(size: 13, weight: .medium, design: .monospaced))
    }

    private func enhancementDetail(_ link: ModelFallbackChain.EnhancementLink) -> String {
        switch link.aiProvider {
        case .ollama?, .localCLI?:
            return String(localized: "On this Mac, works offline")
        case .custom?:
            return String(localized: "Your own provider")
        default:
            return String(localized: "API key")
        }
    }

    private func enhancementSkipReason(_ link: ModelFallbackChain.EnhancementLink) -> String? {
        guard let provider = link.aiProvider else { return String(localized: "Not available") }
        return aiService.connectedProviders.contains(provider) ? nil : String(localized: "Provider not connected")
    }

    private func moveEnhancement(_ link: ModelFallbackChain.EnhancementLink, by offset: Int) {
        guard let from = enhancementLinks.firstIndex(of: link) else { return }
        let to = from + offset
        guard enhancementLinks.indices.contains(to) else { return }
        enhancementLinks.swapAt(from, to)
        commitEnhancementLinks()
    }

    private func moveEnhancement(_ id: String, to target: String) {
        guard let from = enhancementLinks.firstIndex(where: { $0.id == id }),
              let to = enhancementLinks.firstIndex(where: { $0.id == target }) else { return }
        enhancementLinks.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    private func removeEnhancement(_ link: ModelFallbackChain.EnhancementLink) {
        enhancementLinks.removeAll { $0 == link }
        commitEnhancementLinks()
    }

    private func commitEnhancementLinks() {
        ModelFallbackChain.setEnhancementLinks(enhancementLinks)
    }

    // MARK: - Add model

    private struct Candidate: Identifiable {
        let id: String
        let title: String
        let note: String?
        let isAvailable: Bool
        let add: () -> Void
    }

    private var addModelPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search models", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let groups = kind == .transcription ? transcriptionCandidateGroups : enhancementCandidateGroups
                    if groups.allSatisfy({ $0.items.isEmpty }) {
                        Text("No other models to add. Download a model or connect a provider below.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.Text.secondary)
                            .padding(8)
                    }
                    ForEach(groups, id: \.title) { group in
                        if !group.items.isEmpty {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.Text.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 8)

                            ForEach(group.items) { candidate in
                                Button {
                                    candidate.add()
                                    isAddingModel = false
                                } label: {
                                    HStack {
                                        Text(verbatim: candidate.title)
                                            .foregroundStyle(candidate.isAvailable ? AppTheme.Text.primary : AppTheme.Text.secondary)
                                        Spacer(minLength: 8)
                                        if let note = candidate.note {
                                            Text(note)
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppTheme.Text.secondary)
                                        }
                                    }
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
        }
        .padding(12)
        .frame(width: 340)
    }

    private func matchesSearch(_ text: String) -> Bool {
        searchText.isEmpty || text.localizedCaseInsensitiveContains(searchText)
    }

    private var transcriptionCandidateGroups: [(title: String, items: [Candidate])] {
        let remaining = transcriptionModelManager.allAvailableModels.filter { model in
            !transcriptionOrder.contains(model.name)
                && transcriptionModelManager.isAvailableOnCurrentOS(model)
                && matchesSearch(model.displayName + " " + model.name)
        }
        let usable = Set(transcriptionModelManager.usableModels.map(\.name))

        func candidate(_ model: any TranscriptionModel, note: String?) -> Candidate {
            Candidate(
                id: model.name,
                title: model.provider == .custom || [.whisper, .fluidAudio, .nativeApple].contains(model.provider)
                    ? model.displayName
                    : model.provider.rawValue + " " + model.name,
                note: note,
                isAvailable: usable.contains(model.name),
                add: {
                    transcriptionOrder.append(model.name)
                    commitTranscriptionOrder()
                }
            )
        }

        // Local models only once downloaded: the catalog below is where they're fetched.
        let local = remaining
            .filter { [.whisper, .fluidAudio, .nativeApple].contains($0.provider) && usable.contains($0.name) }
            .map { candidate($0, note: $0.provider == .nativeApple ? String(localized: "built in") : String(localized: "downloaded")) }
        let cloud = remaining
            .filter { ![.whisper, .fluidAudio, .nativeApple, .custom].contains($0.provider) }
            .map { candidate($0, note: usable.contains($0.name) ? String(localized: "connected") : String(localized: "no key")) }
        let own = remaining
            .filter { $0.provider == .custom }
            .map { candidate($0, note: nil) }

        return [
            (String(localized: "On this Mac"), local),
            (String(localized: "With an API key"), cloud),
            (String(localized: "Your own server"), own)
        ]
    }

    private var enhancementCandidateGroups: [(title: String, items: [Candidate])] {
        let existing = Set(enhancementLinks.map(\.id))

        func candidates(for provider: AIProvider) -> [Candidate] {
            let models: [String?]
            if provider == .localCLI {
                models = [nil]
            } else {
                let listed = aiService.availableModels(for: provider)
                models = listed.isEmpty ? [provider.defaultModel] : listed.map { Optional($0) }
            }
            return models.compactMap { model in
                let link = ModelFallbackChain.EnhancementLink(provider: provider.rawValue, model: model)
                let title = [provider.rawValue, model].compactMap { $0 }.joined(separator: " ")
                guard !existing.contains(link.id), matchesSearch(title) else { return nil }
                return Candidate(id: link.id, title: title, note: nil, isAvailable: true) {
                    enhancementLinks.append(link)
                    commitEnhancementLinks()
                }
            }
        }

        let connected = aiService.connectedProviders
        let local = connected.filter { $0 == .ollama || $0 == .localCLI }.flatMap(candidates)
        let keyed = connected.filter { ![.ollama, .localCLI, .custom].contains($0) }.flatMap(candidates)
        let own = connected.filter { $0 == .custom }.flatMap(candidates)

        return [
            (String(localized: "On this Mac"), local),
            (String(localized: "With an API key"), keyed),
            (String(localized: "Your own provider"), own)
        ]
    }
}

// MARK: - Pieces

/// One link of the chain: rank stub, name, kind, ready/skipped.
private struct ChainLinkRow: View {
    let rank: Int
    let title: Text
    let detail: String
    let skipReason: String?
    var trailingNote: String? = nil
    var canRemove: Bool = false
    var onRemove: (() -> Void)? = nil
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil

    private var isSkipped: Bool { skipReason != nil }
    private var isMovable: Bool { onMoveUp != nil || onMoveDown != nil || onRemove != nil }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.Palette.rule)
                .opacity(isMovable ? 1 : 0)
                .accessibilityHidden(true)

            rankStub

            VStack(alignment: .leading, spacing: 2) {
                title
                    .foregroundStyle(isSkipped ? AppTheme.Text.secondary : AppTheme.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(skipReason.map { String(format: String(localized: "%@, so Diktilo skips it."), $0) } ?? detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let trailingNote {
                Text(trailingNote)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
            } else {
                statusPill
            }

            if canRemove, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.Text.secondary)
                .help("Remove from the list")
                .accessibilityLabel(Text("Remove from the list"))
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSkipped ? AppTheme.Palette.chip.opacity(0.5) : AppTheme.Palette.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.Palette.rule, style: isSkipped ? AppTheme.Palette.perforation : StrokeStyle(lineWidth: 1))
        )
        .contextMenu {
            if let onMoveUp { Button("Move Up", action: onMoveUp) }
            if let onMoveDown { Button("Move Down", action: onMoveDown) }
            if canRemove, let onRemove { Button("Remove from the list", role: .destructive, action: onRemove) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rankStub: some View {
        let label = Text(verbatim: "\(rank)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .frame(width: 26, height: 26)

        if rank == 1 {
            label
                .foregroundStyle(AppTheme.Palette.onAmber)
                .background(Circle().fill(AppTheme.Palette.amber))
        } else if isSkipped {
            label
                .foregroundStyle(AppTheme.Text.secondary)
                .overlay(Circle().stroke(AppTheme.Palette.rule, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
        } else {
            label
                .foregroundStyle(AppTheme.Text.primary)
                .overlay(Circle().stroke(AppTheme.Text.primary, lineWidth: 1.5))
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            if !isSkipped {
                Circle()
                    .fill(AppTheme.Status.positive)
                    .frame(width: 6, height: 6)
            }
            Text(isSkipped ? LocalizedStringKey("Skipped") : LocalizedStringKey("Ready"))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(isSkipped ? AppTheme.Text.secondary : AppTheme.Text.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(AppTheme.Palette.chip))
    }
}

/// The perforated gap between two links, saying when Diktilo moves on.
private struct ChainConnector: View {
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            VerticalLine()
                .stroke(AppTheme.Palette.rule, style: AppTheme.Palette.perforation)
                .frame(width: 2, height: 30)
                // under the centre of the rank stub: handle 11 + gap 12 + half of 26
                .padding(.leading, 12 + 11 + 12 + 13 - 1)

            Text(reason)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.Text.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private struct VerticalLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            return path
        }
    }
}

/// What happens when every link has failed.
private struct ChainEnding: View {
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.Text.primary)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 40)
        .padding(.vertical, 6)
    }
}

/// Live reordering while a link is dragged over another; the move is saved on drop.
private struct ReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let move: (String, String) -> Void
    let commit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            move(draggingID, targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        commit()
        return true
    }
}
