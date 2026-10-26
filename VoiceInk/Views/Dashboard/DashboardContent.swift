import SwiftUI
import SwiftData

/// Dashboard: what to do first (new users) or the latest transcripts. No
/// numbers and no statistics — those were dropped in the TASK-60.1 redesign.
struct DashboardContent: View {
    let modelContext: ModelContext

    @State private var isAccessibilityEnabled = AXIsProcessTrusted()
    @AppStorage("dashboardRecentTranscriptCount") private var recentTranscriptCount: Int = 8
    @Query(Self.recentTranscriptionsDescriptor()) private var recentTranscriptionCandidates: [Transcription]

    private static func recentTranscriptionsDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        return descriptor
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = DashboardLayout.contentWidth(for: geometry.size.width)

            ScrollView {
                dashboardMainContent(availableWidth: contentWidth)
                    .frame(width: contentWidth, alignment: .top)
                    .frame(
                        minHeight: max(0, geometry.size.height - DashboardLayout.contentBottomOffset),
                        alignment: .top
                    )
                    .padding(.vertical, DashboardLayout.pageVerticalPadding)
                    .padding(.horizontal, DashboardLayout.pageHorizontalPadding)
            }
        }
        .onAppear(perform: refreshAccessibilityStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    private func dashboardMainContent(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionSpacing) {
            if isNewUser {
                DashboardFirstSteps(
                    shortcut: ShortcutStore.shortcut(for: .primaryRecording),
                    isAccessibilityEnabled: isAccessibilityEnabled,
                    hasFirstSession: !recentDashboardTranscriptions.isEmpty,
                    onChangeShortcut: { navigate(to: .modes) },
                    onOpenAccessibilitySettings: openAccessibilitySettings
                )

                if hasHiddenAdvancedFeatures {
                    DashboardMoreHint(onOpenModes: { navigate(to: .modes) })
                }
            } else {
                if !isAccessibilityEnabled {
                    DashboardAccessibilityBar(onOpenSettings: openAccessibilitySettings)
                }

                DashboardTranscriptCards(
                    transcriptions: recentDashboardTranscriptions,
                    onViewAll: { navigate(to: .history) }
                )
            }
        }
        .frame(width: availableWidth, alignment: .topLeading)
    }

    /// True while any of the optional features the hint names is still off.
    private var hasHiddenAdvancedFeatures: Bool {
        [AdvancedFeature.modes, .saveTargets].contains { !$0.isEnabled() }
    }

    /// No displayable session yet: show the checklist instead of an empty list.
    private var isNewUser: Bool {
        recentDashboardTranscriptions.isEmpty
    }

    private var recentDashboardTranscriptions: [Transcription] {
        let count = min(max(recentTranscriptCount, 1), 25)
        return Array(
            recentTranscriptionCandidates
                .filter(isRecentDashboardTranscription)
                .prefix(count)
        )
    }

    private func isRecentDashboardTranscription(_ transcription: Transcription) -> Bool {
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }

        if transcription.transcriptionStatus == TranscriptionStatus.failed.rawValue ||
            transcription.transcriptionStatus == TranscriptionStatus.canceled.rawValue {
            return false
        }

        return text.range(of: "Transcription Failed:", options: [.caseInsensitive, .anchored]) == nil
    }

    private func navigate(to destination: ViewType) {
        NotificationCenter.default.post(
            name: .navigateToDestination,
            object: nil,
            userInfo: ["destination": destination.rawValue]
        )
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Checklist for a user without any session: shortcut, Accessibility, first
/// recording. The state comes from the live system, not stored flags.
private struct DashboardFirstSteps: View {
    let shortcut: Shortcut?
    let isAccessibilityEnabled: Bool
    let hasFirstSession: Bool
    let onChangeShortcut: () -> Void
    let onOpenAccessibilitySettings: () -> Void

    private var doneCount: Int {
        [shortcut != nil, isAccessibilityEnabled, hasFirstSession].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("First steps")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Text.primary)

                Spacer(minLength: 0)

                Text("\(doneCount) of 3")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                step(
                    title: "Recording shortcut set",
                    detail: shortcut?.displayString ?? String(localized: "Choose the shortcut that starts and stops dictation."),
                    isDone: shortcut != nil,
                    actionTitle: "Set Shortcut",
                    action: onChangeShortcut
                )
                step(
                    title: "Accessibility access enabled",
                    detail: String(localized: "Required for shortcuts and typing into other apps."),
                    isDone: isAccessibilityEnabled,
                    actionTitle: "Open Settings",
                    action: onOpenAccessibilitySettings
                )
                step(
                    title: "First session",
                    detail: String(localized: "Press the shortcut, say a sentence, press it again."),
                    isDone: hasFirstSession,
                    actionTitle: nil,
                    action: {}
                )
            }

            if shortcut != nil {
                Button(action: onChangeShortcut) {
                    HStack(spacing: 4) {
                        Text("Change Shortcut")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppCardBackground(cornerRadius: 16))
    }

    private func step(
        title: LocalizedStringKey,
        detail: String,
        isDone: Bool,
        actionTitle: LocalizedStringKey?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? AppTheme.Selection.fill : AppTheme.Surface.controlActive)
                    .frame(width: 28, height: 28)

                Image(systemName: isDone ? "checkmark" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDone ? AppTheme.Text.primary : AppTheme.Text.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primary)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if !isDone, let actionTitle {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }
}

/// Quiet line under the checklist: the hidden features exist and where their
/// switches are (Shortcuts and Modes).
private struct DashboardMoreHint: View {
    let onOpenModes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("More possibilities: Modes and Save Targets — turn them on in Shortcuts and Modes.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)

            link("Shortcuts and Modes", action: onOpenModes)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func link(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.Text.primary)
        }
        .buttonStyle(.plain)
    }
}

/// One-line warning for a user who already has sessions but lost Accessibility
/// access (the shortcuts stop working without it).
private struct DashboardAccessibilityBar: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.Accent.text)

            Text("Shortcuts need Accessibility access.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button("Open Settings", action: onOpenSettings)
                .controlSize(.small)
                .help("Open Accessibility settings")
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Accent.fill)
        )
    }
}
