import SwiftUI
import AppKit

/// Cloud tab of AI Models: providers you have connected first, then the ones
/// you can still connect. Every provider is the same kind of row, whatever it
/// does (aggregator, speech to text, enhancement); the row says what it offers.
struct CloudProviderManagementView: View {
    let selectedProviderID: String?
    let onSelectProvider: (ProviderDescriptor) -> Void

    @State private var showsAllAvailable = false

    private static let collapsedCount = 4

    /// Aggregators first (one key, the easy path for AI enhancement), then
    /// speech-to-text providers, then the enhancement-only vendors. Vendors that
    /// also enhance text (Groq, Gemini, Mistral) appear once, with both abilities.
    static var allDescriptors: [ProviderDescriptor] {
        var seen = Set<String>()
        return (aggregatorDescriptors + transcriptionDescriptors + enhancementOnlyDescriptors)
            .filter { seen.insert($0.id).inserted }
    }

    /// "Cloud 2 of 15" in the tab switcher.
    static var connectionCounts: (connected: Int, total: Int) {
        let all = allDescriptors
        return (all.filter(isConnected).count, all.count)
    }

    static func isConnected(_ descriptor: ProviderDescriptor) -> Bool {
        APIKeyManager.shared.hasAPIKey(forProvider: descriptor.providerKey)
    }

    private static var aggregatorDescriptors: [ProviderDescriptor] {
        AIProvider.allCases.filter(\.isAggregator).map { descriptor(for: $0) }
    }

    private static var transcriptionDescriptors: [ProviderDescriptor] {
        CloudProviderRegistry.allProviders.map { cloudProvider in
            ProviderDescriptor(
                displayName: cloudProvider.providerKey,
                providerKey: cloudProvider.providerKey,
                aiProvider: AIProvider.allCases.first {
                    $0.supportsEnhancement && $0.rawValue.caseInsensitiveCompare(cloudProvider.providerKey) == .orderedSame
                },
                cloudProvider: cloudProvider
            )
        }
    }

    private static var enhancementOnlyDescriptors: [ProviderDescriptor] {
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
        let all = Self.allDescriptors
        let connected = all.filter(Self.isConnected)
        let available = all.filter { !Self.isConnected($0) }

        VStack(alignment: .leading, spacing: 22) {
            if !connected.isEmpty {
                providerGroup(title: "Connected", descriptors: connected, showsAll: nil)
            }

            providerGroup(title: "Available", descriptors: available, showsAll: $showsAllAvailable)

            Text("Connect providers here, then choose a model in each mode (Keyboard Shortcuts).")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
        }
    }

    @ViewBuilder
    private func providerGroup(
        title: LocalizedStringKey,
        descriptors: [ProviderDescriptor],
        showsAll: Binding<Bool>?
    ) -> some View {
        let isCollapsible = showsAll != nil && descriptors.count > Self.collapsedCount + 1
        let isExpanded = showsAll?.wrappedValue ?? true
        let visible = isCollapsible && !isExpanded ? Array(descriptors.prefix(Self.collapsedCount)) : descriptors
        let hidden = descriptors.dropFirst(visible.count)

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.Text.primary)

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

    private static func descriptor(for aiProvider: AIProvider) -> ProviderDescriptor {
        ProviderDescriptor(
            displayName: aiProvider.rawValue,
            providerKey: aiProvider.rawValue,
            aiProvider: aiProvider,
            cloudProvider: matchingCloudProvider(for: aiProvider)
        )
    }

    private static func matchingCloudProvider(for aiProvider: AIProvider) -> (any CloudProvider)? {
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

        if descriptor.aiProvider?.isAggregator == true {
            parts.append(String(localized: "One key, many models"))
        }

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

                actionLabel
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? AppTheme.Selection.fill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Looks like a button; the whole row is the button, so it can't nest one.
    @ViewBuilder
    private var actionLabel: some View {
        if isConfigured {
            Text("Manage")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primary)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .overlay(Capsule().strokeBorder(AppTheme.Palette.ink, lineWidth: 1.5))
        } else {
            Text("Connect")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.onAmber)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(AppTheme.Palette.amber))
        }
    }
}
