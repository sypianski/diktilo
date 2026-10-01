import SwiftUI

/// "Local or with an API key?" in plain words, side by side. Used where the
/// user first meets the choice: onboarding, the tour and AI Models.
struct LocalOrKeyExplainer: View {
    enum Subject {
        /// Speech to text: what happens to the recording.
        case transcription
        /// AI enhancement: what happens to the text.
        case enhancement
    }

    var subject: Subject = .transcription
    /// Self-hosted servers and the same choice for enhancement (AI Models).
    var showsMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                column(
                    icon: "macbook",
                    title: localTitle,
                    text: localText
                )

                column(
                    icon: "key",
                    title: "API key",
                    text: keyText
                )
            }

            if showsMore {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Own server: a custom model can point to a server of your own (e.g. speaches), and recordings go only there.")
                    Text("The same choice applies to AI enhancement: locally through Ollama or with a provider's key.")
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var localTitle: LocalizedStringKey {
        switch subject {
        case .transcription: return "Local model"
        case .enhancement: return "Local model (Ollama)"
        }
    }

    private var localText: LocalizedStringKey {
        switch subject {
        case .transcription:
            return "Runs on your Mac. Your recordings never leave the computer and it works offline. You download it once; its speed depends on your Mac."
        case .enhancement:
            return "AI rewrites your text on your Mac. Nothing leaves the computer and it works offline, but you need Ollama installed and a fairly powerful Mac."
        }
    }

    private var keyText: LocalizedStringKey {
        switch subject {
        case .transcription:
            return "The recording goes to an outside provider (e.g. Groq, OpenAI, ElevenLabs), which sends back the text. The key is your personal ID with that provider: you create an account, copy the key and paste it into Diktilo. You pay the provider for use, often with a free allowance. Needs internet; recordings go to the provider's servers."
        case .enhancement:
            return "The text (not the recording) goes to a provider such as Groq or OpenAI, which sends back the rewritten version. You create an account there, copy the key and paste it into Diktilo. You pay for use, often with a free allowance."
        }
    }

    private func column(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AppTheme.Text.primary)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Palette.chip.opacity(0.55))
        )
    }
}

/// The explainer as the first card of AI Models: the choice everything else on
/// that screen depends on, so it starts expanded; folding it is remembered.
struct LocalOrKeyCard: View {
    @AppStorage("ModelsLocalOrKeyExpanded") private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LocalOrKeyExplainer(showsMore: true)
                .padding(.top, 10)
        } label: {
            Text("Local or with an API key?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.card))
    }
}

/// The explainer folded under one line, for screens without room to spare
/// (onboarding): the line says the gist, the disclosure the details.
struct LocalOrKeyDisclosure: View {
    var subject: LocalOrKeyExplainer.Subject = .transcription

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LocalOrKeyExplainer(subject: subject)
                .padding(.top, 8)
        } label: {
            Text("Local or with an API key?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
        }
    }
}
