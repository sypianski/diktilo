import SwiftUI

/// Both dictionary sections on one page. The quick-add shortcut is a chip in
/// the header; the vocabulary section warns only when no mode can use it.
struct DictionarySettingsView: View {
    @State private var isShowingShortcutPopover = false
    @ObservedObject private var modeManager = OutputProfileManager.shared

    var body: some View {
        VStack(spacing: 0) {
            AppScreenHeader(title: "Personal Dictionary") {
                shortcutChip
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    section(
                        title: "Word Replacements",
                        detail: "Word Replacements run after transcription to replace misheard words, phrases, abbreviations, or boilerplate text."
                    ) {
                        WordReplacementView()
                    }

                    section(
                        title: "Vocabulary",
                        detail: "Vocabulary is used only with AI enhancement to preserve important names, technical terms, and unique spellings in the final output."
                    ) {
                        if !isVocabularyUsable {
                            vocabularyWarning
                        }
                        VocabularyView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    /// Vocabulary goes to the AI model, so it does nothing while no mode
    /// has AI enhancement switched on.
    private var isVocabularyUsable: Bool {
        modeManager.enabledConfigurations.contains { $0.isAIEnhancementEnabled }
    }

    private var shortcutChip: some View {
        Button {
            isShowingShortcutPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .medium))
                Text("Quick Add")
                    .font(.system(size: 12, weight: .medium))
                Text(ShortcutStore.shortcut(for: .quickAddToDictionary)?.displayString ?? String(localized: "Not Set"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .foregroundStyle(AppTheme.Text.primary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(AppTheme.Surface.controlActive))
        }
        .buttonStyle(.plain)
        .help("Quick Add to Dictionary")
        .popover(isPresented: $isShowingShortcutPopover) {
            LabeledContent("Quick Add to Dictionary") {
                ShortcutRecorder(action: .quickAddToDictionary)
                    .controlSize(.small)
            }
            .padding(14)
            .frame(width: 340)
        }
    }

    private var vocabularyWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Accent.text)

            Text("No mode has AI enhancement on, so vocabulary has no effect yet.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": ViewType.modes.rawValue]
                )
            } label: {
                HStack(spacing: 4) {
                    Text("Modes")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Accent.fill)
        )
    }

    private func section<Content: View>(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.Surface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.Border.control.opacity(0.16), lineWidth: 1)
            )
        }
    }
}
