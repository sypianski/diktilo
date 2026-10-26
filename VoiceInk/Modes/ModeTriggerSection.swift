import SwiftUI

struct ModeTriggerSection: View {
    @Binding var appConfigs: [AppConfig]
    @Binding var websiteConfigs: [URLConfig]
    @Binding var triggerGroups: [ModeTriggerGroup]
    @Binding var triggerWords: [String]
    let profileId: UUID
    let cleanURL: (String) -> String

    @EnvironmentObject private var modeWarmupStore: OutputProfileFormWarmupStore

    @State private var triggerSearchText = ""
    /// Open from the start only when the mode already has triggers; the content
    /// (and its app scan) is not built while folded.
    @State private var isExpanded: Bool

    init(
        appConfigs: Binding<[AppConfig]>,
        websiteConfigs: Binding<[URLConfig]>,
        triggerGroups: Binding<[ModeTriggerGroup]>,
        triggerWords: Binding<[String]>,
        profileId: UUID,
        cleanURL: @escaping (String) -> String
    ) {
        _appConfigs = appConfigs
        _websiteConfigs = websiteConfigs
        _triggerGroups = triggerGroups
        _triggerWords = triggerWords
        self.profileId = profileId
        self.cleanURL = cleanURL
        _isExpanded = State(initialValue:
            !appConfigs.wrappedValue.isEmpty
                || !websiteConfigs.wrappedValue.isEmpty
                || !triggerGroups.wrappedValue.isEmpty
                || !triggerWords.wrappedValue.isEmpty
        )
    }

    private var hasSelectedTriggers: Bool {
        !triggerGroups.isEmpty || !appConfigs.isEmpty || !websiteConfigs.isEmpty || !triggerWords.isEmpty
    }

    /// "Apps: 2, Websites: 1, Words: 1" — counts include what trigger groups
    /// bring along. Label-first wording avoids plural rules per language.
    private var triggerSummary: LocalizedStringKey {
        guard hasSelectedTriggers else { return "No triggers" }

        let apps = appConfigs.count + triggerGroups.reduce(0) { $0 + $1.appConfigs.count }
        let websites = websiteConfigs.count + triggerGroups.reduce(0) { $0 + $1.urlConfigs.count }
        var parts: [String] = []
        if apps > 0 { parts.append(String(localized: "Apps: \(apps)")) }
        if websites > 0 { parts.append(String(localized: "Websites: \(websites)")) }
        if !triggerWords.isEmpty { parts.append(String(localized: "Words: \(triggerWords.count)")) }
        if parts.isEmpty { parts.append(String(localized: "Trigger groups: \(triggerGroups.count)")) }
        return LocalizedStringKey(parts.joined(separator: ", "))
    }

    var body: some View {
        Section {
            ExpandableSettingsRow(
                title: "Triggers",
                isExpanded: $isExpanded,
                isEnabled: nil,
                summary: "Diktilo switches to this mode on its own for chosen apps, websites or a spoken trigger word.",
                statusNote: triggerSummary,
                infoMessage: "Diktilo automatically switches to this mode based on the app or website you're using, or when you say a trigger word during recording."
            ) {
                triggerContent
            }
        }
    }

    @ViewBuilder
    private var triggerContent: some View {
        if hasSelectedTriggers {
            ModeTriggerSelectionView(
                appConfigs: $appConfigs,
                websiteConfigs: $websiteConfigs,
                triggerGroups: $triggerGroups,
                triggerWords: $triggerWords,
                installedApps: modeWarmupStore.installedApps,
                cleanURL: cleanURL,
                loadInstalledAppsIfNeeded: modeWarmupStore.refreshInstalledApps
            )
            .padding(.vertical, 2)
        } else {
            emptyTriggerState
        }

        TriggerPickerPopover(
            installedApps: modeWarmupStore.installedApps,
            isLoadingApps: modeWarmupStore.isLoadingInstalledApps,
            currentModeId: profileId,
            appConfigs: $appConfigs,
            websiteConfigs: $websiteConfigs,
            triggerGroups: $triggerGroups,
            triggerWords: $triggerWords,
            searchText: $triggerSearchText,
            cleanURL: cleanURL,
            isInline: true
        )
        .onAppear { modeWarmupStore.refreshInstalledApps() }
    }

    private var emptyTriggerState: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No automatic triggers")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
