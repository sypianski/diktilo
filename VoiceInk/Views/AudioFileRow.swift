import SwiftUI

struct AudioFileRow: View {
    @ObservedObject var item: AudioFileQueueItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void
    let onShowInHistory: () -> Void
    let onChooseModel: () -> Void

    @State private var selectedTab: TranscriptionTab = .original

    private var displayText: String {
        switch selectedTab {
        case .original:
            return item.transcription?.text ?? ""
        case .enhanced:
            return item.transcription?.enhancedText ?? ""
        }
    }

    /// Text for copy/save — matches visible content regardless of expansion state.
    private var actionText: String {
        if isExpanded {
            return displayText
        }
        return item.transcription?.enhancedText ?? item.transcription?.text ?? ""
    }

    /// "3:21 · 4.2 MB", whichever parts are known.
    private var metaLine: String? {
        var parts: [String] = []
        if let duration = item.duration, duration > 0 {
            parts.append(formatDuration(duration))
        }
        if let size = item.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        switch item.status {
        case .pending:
            pendingRow
        case .processing(let phase):
            processingRow(phase: phase)
        case .completed:
            completedRows
        case .failed(let message):
            failedRow(message: message)
        }
    }

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove from list")
    }

    private func nameAndMeta(nameColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.filename)
                .foregroundColor(nameColor)
                .lineLimit(1)
                .truncationMode(.middle)

            if let metaLine {
                Text(metaLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Pending

    private var pendingRow: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)

            nameAndMeta()

            Spacer()

            Text("Waiting")
                .font(.caption)
                .foregroundColor(.secondary)

            removeButton
        }
    }

    // MARK: - Processing

    private func processingRow(phase: QueueItemStatus.ProcessingPhase) -> some View {
        HStack {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)

            nameAndMeta()

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(LocalizedStringKey(phase.rawValue))
                    .font(.caption)
                    .foregroundColor(AppTheme.Accent.text)

                stepTrack
            }
        }
    }

    /// Four segments for loading, audio, transcription and enhancement;
    /// everything up to the running step is filled.
    private var stepTrack: some View {
        let current = item.status.stepNumber ?? 0

        return HStack(spacing: 3) {
            ForEach(1...QueueItemStatus.stepCount, id: \.self) { step in
                Capsule()
                    .fill(step <= current ? AppTheme.Accent.primary : AppTheme.Accent.fillSubtle)
                    .frame(width: 16, height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: String(localized: "Step %lld of %lld"), current, QueueItemStatus.stepCount)
        )
    }

    // MARK: - Completed

    @ViewBuilder
    private var completedRows: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.Status.positive)

            Text(item.filename)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !isExpanded, let transcription = item.transcription {
                Text(transcription.enhancedText ?? transcription.text)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let transcription = item.transcription {
                if !isExpanded {
                    HStack(spacing: 2) {
                        CopyIconButton(textToCopy: actionText)
                        SaveIconButton(textToSave: actionText)
                    }
                }

                if transcription.duration > 0 {
                    Text(formatDuration(transcription.duration))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpand() }

        if isExpanded, let transcription = item.transcription {
            if transcription.enhancedText != nil {
                HStack(spacing: 4) {
                    tabButton(tab: .original)
                    tabButton(tab: .enhanced)
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

            HStack(spacing: 12) {
                if let model = transcription.transcriptionModelName {
                    Label(model, systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let prompt = transcription.promptName {
                    Label(prompt, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            resultActions
        }
    }

    /// Footer of an expanded result: what can be done with the text, and where it already lives.
    private var resultActions: some View {
        HStack(spacing: 8) {
            CopyIconButton(textToCopy: actionText, showsTitle: true)
            SaveIconButton(textToSave: actionText, showsTitle: true)

            Button {
                onShowInHistory()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Show in History")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(AppTheme.Accent.text)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(Capsule().fill(AppTheme.Accent.fillSubtle))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Saved in History")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func tabButton(tab: TranscriptionTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(LocalizedStringKey(tab.rawValue))
                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundColor(selectedTab == tab ? AppTheme.Accent.primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedTab == tab ? AppTheme.Accent.fill : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Failed

    private func failedRow(message: String) -> some View {
        let needsModel = message == TranscriptionError.noModelSelected.errorDescription

        return HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(AppTheme.Status.error)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(message)
                    .font(.caption)
                    .foregroundColor(AppTheme.Status.error.opacity(0.80))
                    .lineLimit(2)

                if needsModel {
                    Button {
                        onChooseModel()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Choose a model in AI Models")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.Accent.text)
                }
            }

            Spacer()

            Button {
                onRetry()
            } label: {
                Label("Retry", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            removeButton
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// A file that was dropped or chosen but never entered the queue, with the reason.
struct SkippedFileRow: View {
    let file: SkippedQueueFile
    let onRemove: () -> Void

    private var reason: LocalizedStringKey {
        switch file.reason {
        case .unsupportedFormat: return "Unsupported format"
        case .alreadyQueued: return "Already in the list"
        case .missing: return "File not found"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: "minus.circle")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from list")
        }
        .opacity(0.8)
    }
}
