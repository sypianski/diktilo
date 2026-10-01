import SwiftUI
import AppKit

/// Cloud tab of AI Models: aggregators first (one key, many models, the easy
/// path for AI enhancement), then speech-to-text providers, then the
/// enhancement-only vendors. Every row and card opens the provider panel.
struct CloudProviderManagementView: View {
    let selectedProviderID: String?
    let onSelectProvider: (ProviderDescriptor) -> Void

    @State private var showsAllTranscription = false

    private static let collapsedCount = 4

    private var aggregatorDescriptors: [ProviderDescriptor] {
        AIProvider.allCases.filter(\.isAggregator).map { descriptor(for: $0) }
    }

    /// Speech-to-text providers, connected ones first. Vendors that also
    /// enhance text (Groq, Gemini, Mistral) live here with both abilities.
    private var transcriptionDescriptors: [ProviderDescriptor] {
        let descriptors = CloudProviderRegistry.allProviders.map { cloudProvider in
            ProviderDescriptor(
                displayName: cloudProvider.providerKey,
                providerKey: cloudProvider.providerKey,
                aiProvider: AIProvider.allCases.first {
                    $0.supportsEnhancement && $0.rawValue.caseInsensitiveCompare(cloudProvider.providerKey) == .orderedSame
                },
                cloudProvider: cloudProvider
            )
        }
        return descriptors.enumerated().sorted { first, second in
            let firstConnected = APIKeyManager.shared.hasAPIKey(forProvider: first.element.providerKey)
            let secondConnected = APIKeyManager.shared.hasAPIKey(forProvider: second.element.providerKey)
            if firstConnected != secondConnected { return firstConnected }
            return first.offset < second.offset
        }.map(\.element)
    }

    private var enhancementOnlyDescriptors: [ProviderDescriptor] {
        let preferredOrder: [AIProvider] = [.openAI, .anthropic, .cerebras]
        return AIProvider.allCases
            .filter { provider in
                provider.supportsEnhancement && provider.requiresAPIKey && !provider.isAggregator &&
                    provider != .custom && matchingCloudProvider(for: provider) == nil
            }
            .sorted { (preferredOrder.firstIndex(of: $0) ?? Int.max) < (preferredOrder.firstIndex(of: $1) ?? Int.max) }
            .map { descriptor(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            aggregatorSection

            providerGroup(
                title: "Transcription in the Cloud",
                note: "Aggregators don't turn speech into text.",
                descriptors: transcriptionDescriptors,
                showsAll: $showsAllTranscription
            )

            providerGroup(
                title: "Individual AI Providers",
                note: "Groq, Gemini and Mistral also enhance text; they're listed above.",
                descriptors: enhancementOnlyDescriptors,
                showsAll: nil
            )

            Text("Connect providers here, then choose a model in each mode (Keyboard Shortcuts).")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
        }
    }

    private var aggregatorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("One Key, Many Models")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.Text.primary)
                Text("For AI enhancement an aggregator is the easiest choice: one key gives you Claude, GPT, Gemini or Llama, you pay in one place, and backup models need no extra accounts.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(aggregatorDescriptors) { descriptor in
                    AggregatorCard(
                        descriptor: descriptor,
                        isSelected: selectedProviderID == descriptor.id,
                        onSelect: { onSelectProvider(descriptor) }
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Palette.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.Palette.ink, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func providerGroup(
        title: LocalizedStringKey,
        note: LocalizedStringKey,
        descriptors: [ProviderDescriptor],
        showsAll: Binding<Bool>?
    ) -> some View {
        let isCollapsible = showsAll != nil && descriptors.count > Self.collapsedCount + 1
        let isExpanded = showsAll?.wrappedValue ?? true
        let visible = isCollapsible && !isExpanded ? Array(descriptors.prefix(Self.collapsedCount)) : descriptors
        let hidden = descriptors.dropFirst(visible.count)

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.Text.primary)
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, descriptor in
                    if index > 0 {
                        PerforationRule()
                            .padding(.horizontal, 12)
                    }
                    CompactProviderRow(
                        descriptor: descriptor,
                        isSelected: selectedProviderID == descriptor.id,
                        onSelect: { onSelectProvider(descriptor) }
                    )
                }

                if isCollapsible, let showsAll {
                    PerforationRule()
                        .padding(.horizontal, 12)
                    HStack(spacing: 12) {
                        if !isExpanded {
                            Text(hidden.map(\.displayName).joined(separator: ", "))
                                .font(.system(size: 12.5))
                                .foregroundStyle(AppTheme.Text.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                        Button(isExpanded ? LocalizedStringKey("Show Fewer") : LocalizedStringKey("Show All")) {
                            withAnimation(.easeInOut(duration: 0.2)) { showsAll.wrappedValue.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.Accent.text)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .background(AppMaterialCardBackground(cornerRadius: AppTheme.Radius.card))
        }
    }

    private func descriptor(for aiProvider: AIProvider) -> ProviderDescriptor {
        ProviderDescriptor(
            displayName: aiProvider.rawValue,
            providerKey: aiProvider.rawValue,
            aiProvider: aiProvider,
            cloudProvider: matchingCloudProvider(for: aiProvider)
        )
    }

    private func matchingCloudProvider(for aiProvider: AIProvider) -> (any CloudProvider)? {
        CloudProviderRegistry.allProviders.first {
            $0.providerKey.caseInsensitiveCompare(aiProvider.rawValue) == .orderedSame
        }
    }
}

struct ProviderDescriptor: Identifiable {
    let displayName: String
    let providerKey: String
    let aiProvider: AIProvider?
    let cloudProvider: (any CloudProvider)?

    var id: String { providerKey }

    var transcriptionModels: [CloudModel] {
        cloudProvider?.models ?? []
    }

    var hasTranscription: Bool {
        !transcriptionModels.isEmpty
    }

    var hasEnhancement: Bool {
        aiProvider != nil
    }

    var brandAssetName: String? {
        switch providerKey.lowercased() {
        case "openai":
            return "provider-openai"
        case "openrouter":
            return "provider-openrouter"
        case "anthropic":
            return "provider-anthropic"
        case "gemini":
            return "provider-gemini"
        case "groq":
            return "provider-groq"
        case "mistral":
            return "provider-mistral"
        case "cerebras":
            return "provider-cerebras"
        case "deepgram":
            return "provider-deepgram"
        case "elevenlabs":
            return "provider-elevenlabs"
        case "soniox":
            return "provider-soniox"
        case "speechmatics":
            return "provider-speechmatics"
        case "assemblyai":
            return "provider-assemblyai"
        case "xai":
            return "provider-xai"
        case "cartesia":
            return "provider-cartesia"
        default:
            return nil
        }
    }

    var apiConsoleURL: URL? {
        switch providerKey.lowercased() {
        case "groq":
            return URL(string: "https://console.groq.com/keys")
        case "cerebras":
            return URL(string: "https://cloud.cerebras.ai/platform")
        case "gemini":
            return URL(string: "https://aistudio.google.com/app/apikey")
        case "openai":
            return URL(string: "https://platform.openai.com/api-keys")
        case "openrouter":
            return URL(string: "https://openrouter.ai/keys")
        case "requesty":
            return URL(string: "https://app.requesty.ai/api-keys")
        case "anthropic":
            return URL(string: "https://console.anthropic.com/settings/keys")
        case "mistral":
            return URL(string: "https://console.mistral.ai/api-keys/")
        case "deepgram":
            return URL(string: "https://console.deepgram.com/project/keys")
        case "elevenlabs":
            return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        case "soniox":
            return URL(string: "https://console.soniox.com/api-keys")
        case "speechmatics":
            return URL(string: "https://console.speechmatics.com/")
        case "assemblyai":
            return URL(string: "https://www.assemblyai.com/dashboard/signup")
        case "xai":
            return URL(string: "https://console.x.ai/")
        case "cartesia":
            return URL(string: "https://play.cartesia.ai/keys")
        default:
            return nil
        }
    }
}

/// A bigger card for an aggregator: what it gives you and one clear action.
private struct AggregatorCard: View {
    @EnvironmentObject private var aiService: AIService

    let descriptor: ProviderDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    private var isConfigured: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: descriptor.providerKey)
    }

    private var modelCountText: String {
        let count = descriptor.aiProvider.map { aiService.availableModels(for: $0).count } ?? 0
        guard count > 0 else { return String(localized: "model router") }
        return String(format: String(localized: "Models: %lld"), Int64(count))
    }

    private var summary: LocalizedStringKey {
        descriptor.aiProvider == .requesty
            ? "One key for many vendors, with a cost dashboard and spending limits."
            : "Models from all the major vendors under one key, with the price shown next to each model."
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProviderBrandIcon(
                        descriptor: descriptor,
                        fallbackSystemImage: "arrow.triangle.branch",
                        isSelected: isSelected,
                        size: 34,
                        iconSize: 16
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(descriptor.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.Text.primary)
                        Text(modelCountText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.Text.secondary)
                    }
                }

                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    ProviderStatusBadge(
                        title: isConfigured ? "Connected" : "Not connected",
                        color: isConfigured ? AppTheme.Status.positive : AppTheme.Text.secondary
                    )
                    Spacer(minLength: 8)
                    actionLabel
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppTheme.Palette.chip : AppTheme.Palette.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.Palette.rule, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isConfigured ? Text("Choose Models") : Text("Connect"))
    }

    /// Looks like a button; the whole card is the button, so it can't nest one.
    @ViewBuilder
    private var actionLabel: some View {
        if isConfigured {
            Text("Choose Models")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .overlay(Capsule().strokeBorder(AppTheme.Palette.ink, lineWidth: 1.5))
        } else {
            Text("Connect")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.onAmber)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(AppTheme.Palette.amber))
        }
    }
}

/// One line of a provider list; rows of a group share one card, split by
/// perforation.
private struct CompactProviderRow: View {
    @EnvironmentObject private var aiService: AIService

    let descriptor: ProviderDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    private var isConfigured: Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: descriptor.providerKey)
    }

    private var iconName: String {
        if descriptor.hasTranscription && descriptor.hasEnhancement { return "rectangle.2.swap" }
        if descriptor.hasTranscription { return "captions.bubble.fill" }
        return "sparkles"
    }

    private var capabilitySummary: String {
        var parts: [String] = []

        let transcriptionCount = descriptor.transcriptionModels.count
        if transcriptionCount > 0 {
            parts.append(String.localizedStringWithFormat(
                NSLocalizedString("%lld Transcription models", comment: "Number of transcription models available for a provider."),
                Int64(transcriptionCount)
            ))
        }

        if let provider = descriptor.aiProvider {
            parts.append(String.localizedStringWithFormat(
                NSLocalizedString("%lld Enhancement models", comment: "Number of enhancement models available for a provider."),
                Int64(aiService.availableModels(for: provider).count)
            ))
        }

        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ProviderBrandIcon(
                    descriptor: descriptor,
                    fallbackSystemImage: iconName,
                    isSelected: isSelected,
                    size: 24,
                    iconSize: 13
                )

                Text(descriptor.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text(capabilitySummary)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                ProviderStatusBadge(
                    title: isConfigured ? "Connected" : "Not connected",
                    color: isConfigured ? AppTheme.Status.positive : AppTheme.Text.secondary
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? AppTheme.Selection.fill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
