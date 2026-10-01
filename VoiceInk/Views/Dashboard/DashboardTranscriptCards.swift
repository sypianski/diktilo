import SwiftUI

struct DashboardTranscriptCards: View {
    let transcriptions: [Transcription]
    /// When set, a "View All" affordance is shown next to the title (e.g. to
    /// open the full History tab). Nil hides it.
    var onViewAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Recent Transcripts")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.Text.primary)
                    .lineLimit(1)

                if let onViewAll {
                    Spacer(minLength: 0)
                    Button(action: onViewAll) {
                        HStack(spacing: 4) {
                            Text("View All")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.Text.primary)
                    }
                    .buttonStyle(.plain)
                    .help("Open the full transcription history")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(transcriptions.enumerated()), id: \.element.id) { index, transcription in
                    DashboardTranscriptCardRow(transcription: transcription)

                    if index < transcriptions.count - 1 {
                        PerforationRule()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardTranscriptCardRow: View {
    private static let metaColumnWidth: CGFloat = 96
    private static let rowSpacing: CGFloat = 16
    private static let copyButtonSize: CGFloat = 28
    private static let copyButtonTopInset: CGFloat = 12
    private static let copyButtonTrailingInset: CGFloat = 6

    let transcription: Transcription
    @State private var isHovering = false
    @State private var isExpanded = false

    private var previewText: String {
        Self.normalizedPreviewText(displayText)
    }

    private var copyText: String {
        displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayText: String {
        if let enhancedText = transcription.enhancedText,
           Self.isUsableEnhancedText(enhancedText) {
            return enhancedText
        }

        return transcription.text
    }

    private var metadataText: String {
        transcription.timestamp.formatted(.relative(presentation: .named))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private var modeIcon: ModeIcon {
        guard let iconValue = transcription.modeEmoji?.trimmingCharacters(in: .whitespacesAndNewlines),
              !iconValue.isEmpty else {
            return .symbol("doc.text")
        }

        if Self.isLikelySymbolName(iconValue) {
            return .symbol(iconValue)
        }

        return .emoji(iconValue)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            rowContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    isExpanded.toggle()
                }
                .accessibilityAddTraits(.isButton)

            CopyIconButton(textToCopy: copyText, accessibilityLabel: "Copy transcript")
                .frame(width: Self.copyButtonSize, height: Self.copyButtonSize)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .padding(.top, Self.copyButtonTopInset)
                .padding(.trailing, Self.copyButtonTrailingInset)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcript from \(metadataText)")
        .accessibilityValue(isExpanded ? copyText : previewText)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: Self.rowSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transcription.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.primary)

                    ModeIconView(
                        icon: modeIcon,
                        size: modeIcon.kind == .emoji ? 12 : 11,
                        color: AppTheme.Text.secondary
                    )
                }

                Text(Self.dayFormatter.string(from: transcription.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .lineLimit(1)
            .frame(width: Self.metaColumnWidth, alignment: .leading)

            Text(isExpanded ? copyText : previewText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppTheme.Text.primary)
                .lineSpacing(2)
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
    }

    private static func isUsableEnhancedText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return trimmed.range(of: "Enhancement failed:", options: [.caseInsensitive, .anchored]) == nil
    }

    private static func normalizedPreviewText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isLikelySymbolName(_ value: String) -> Bool {
        let symbolNameCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._")

        return value.unicodeScalars.allSatisfy { scalar in
            symbolNameCharacters.contains(scalar)
        }
    }
}
