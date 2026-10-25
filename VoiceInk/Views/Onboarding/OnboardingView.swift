import SwiftUI
import AppKit

struct OnboardingView: View {
    @Binding var hasCompletedOnboardingV2: Bool
    @EnvironmentObject var fluidAudioModelManager: FluidAudioModelManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var enhancementService: AIEnhancementService
    @StateObject private var coordinator = OnboardingCoordinator()

    let contentMaxWidth: CGFloat = 560

    var body: some View {
        let isTranscriptionModelDownloaded = coordinator.isTranscriptionModelDownloaded(
            using: fluidAudioModelManager
        )
        let isTranscriptionSetupReady = coordinator.isTranscriptionSetupReady(
            isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
        )

        ZStack(alignment: .top) {
            OnboardingBackground()

            Group {
                switch coordinator.stage {
                case .trust:
                    OnboardingTrustScreen(
                        contentMaxWidth: contentMaxWidth,
                        onContinue: coordinator.flow.goToPermissionsStep
                    )
                        .transition(.opacity)
                case .permissions:
                    OnboardingPermissionsScreen(
                        contentMaxWidth: contentMaxWidth,
                        isComplete: coordinator.requiredPermissionsGranted,
                        isMicrophoneSelected: coordinator.hasSelectedOnboardingMicrophone,
                        isMicrophoneGranted: coordinator.permissions.status(for: .microphone).isGranted,
                        activePermission: coordinator.activePermission,
                        stepNumber: { coordinator.permissions.stepNumber(for: $0) },
                        status: { coordinator.permissions.status(for: $0) },
                        isLocked: { coordinator.permissions.isLocked($0) },
                        actionTitle: { coordinator.permissions.actionTitle(for: $0) },
                        onSelect: coordinator.permissions.setActivePermission,
                        onAction: coordinator.permissions.performAction,
                        onMicrophoneSelected: { coordinator.objectWillChange.send() },
                        onBack: coordinator.flow.goToTrustStep,
                        onRecheck: coordinator.permissions.refreshPermissionStatuses,
                        onContinue: coordinator.flow.goToModelStep
                    )
                        .transition(.opacity)
                case .model:
                    OnboardingModelScreen(
                        contentMaxWidth: contentMaxWidth,
                        localModel: coordinator.requiredTranscriptionModel,
                        setupKind: coordinator.transcriptionSetupKind,
                        providerOptions: coordinator.onboardingTranscriptionProviderOptions,
                        selectedProviderKey: coordinator.selectedOnboardingTranscriptionProviderKeyBinding(),
                        isLocalDownloaded: isTranscriptionModelDownloaded,
                        isLocalDownloading: coordinator.requiredTranscriptionModel.map {
                            fluidAudioModelManager.isFluidAudioModelDownloading($0)
                        } ?? false,
                        localDownloadStatus: coordinator.requiredTranscriptionModel.flatMap {
                            fluidAudioModelManager.downloadStatus(for: $0)
                        },
                        isSetupReady: isTranscriptionSetupReady,
                        onSelectSetupKind: coordinator.flow.selectOnboardingTranscriptionSetup,
                        onDownload: {
                            coordinator.flow.downloadTranscriptionModel(
                                $0,
                                modelManager: fluidAudioModelManager
                            )
                        },
                        onVerificationChanged: coordinator.flow.refreshTranscriptionSetupVerification,
                        onBack: coordinator.flow.goToPermissionsStep,
                        onContinue: {
                            coordinator.flow.goToAPIStep(
                                isTranscriptionSetupReady: isTranscriptionSetupReady,
                                aiService: aiService
                            )
                        }
                    )
                        .transition(.opacity)
                case .api:
                    OnboardingAPIScreen(
                        aiService: aiService,
                        contentMaxWidth: contentMaxWidth,
                        providerOptions: coordinator.onboardingProviderOptions,
                        selectedProvider: coordinator.selectedOnboardingProviderBinding(aiService: aiService),
                        isSelectedProviderVerified: coordinator.isSelectedAPIProviderVerified,
                        onVerificationChanged: coordinator.flow.refreshAPIVerification,
                        onBack: coordinator.flow.goBackToModelStep,
                        onContinue: {
                            coordinator.flow.continueFromAPIStep(
                                isTranscriptionSetupReady: isTranscriptionSetupReady,
                                enhancementService: enhancementService
                            )
                        }
                    )
                        .transition(.opacity)
                case .experience:
                    OnboardingExperienceScreen(
                        step: coordinator.experienceStep,
                        shortcutAction: coordinator.experienceShortcutAction,
                        hasShortcut: coordinator.hasExperienceModeShortcut,
                        text: coordinator.currentExperienceText,
                        isReady: coordinator.isCurrentExperienceReady(
                            isTranscriptionSetupReady: isTranscriptionSetupReady
                        ),
                        isComplete: coordinator.isCurrentExperienceComplete,
                        onBack: {
                            coordinator.flow.goToPreviousExperienceStep(enhancementService: enhancementService)
                        },
                        onAdvance: {
                            coordinator.flow.advanceExperienceStep(
                                isTranscriptionSetupReady: isTranscriptionSetupReady,
                                enhancementService: enhancementService
                            )
                        },
                        onShortcutChanged: {
                            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
                        },
                        onAppear: coordinator.flow.activateExperienceModeForDemo
                    )
                        .transition(.opacity)
                case .summary:
                    OnboardingSummaryScreen(
                        contentMaxWidth: contentMaxWidth,
                        rows: summaryRows,
                        onBack: {
                            coordinator.flow.goToPreviousSummaryStep(
                                isTranscriptionSetupReady: isTranscriptionSetupReady,
                                enhancementService: enhancementService
                            )
                        },
                        onSeeGuide: {
                            finish(isTranscriptionSetupReady: isTranscriptionSetupReady, showsGuide: true)
                        },
                        onStart: {
                            finish(isTranscriptionSetupReady: isTranscriptionSetupReady, showsGuide: false)
                        }
                    )
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingProgressBar(
                currentStep: coordinator.currentStepNumber,
                totalSteps: coordinator.totalStepCount
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 18)
            .allowsHitTesting(false)
        }
        .frame(minWidth: 820, minHeight: 680)
        .animation(.easeInOut(duration: 0.22), value: coordinator.stage)
        .onAppear {
            coordinator.flow.ensureDefaultOnboardingTranscriptionProvider()
            coordinator.flow.refreshTranscriptionSetupVerification()
            coordinator.flow.ensureDefaultOnboardingProvider()
            coordinator.permissions.refreshPermissionStatuses()
            coordinator.flow.refreshAPIVerification()
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
            let refreshedTranscriptionSetupReady = coordinator.isTranscriptionSetupReady(
                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
            )
            coordinator.flow.reconcileStage(
                isTranscriptionSetupReady: refreshedTranscriptionSetupReady,
                enhancementService: enhancementService
            )
        }
        .onDisappear {
            coordinator.permissions.cancelRefreshTask()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.permissions.refreshPermissionStatuses()
            coordinator.flow.refreshTranscriptionSetupVerification()
            let refreshedTranscriptionSetupReady = coordinator.isTranscriptionSetupReady(
                isTranscriptionModelDownloaded: isTranscriptionModelDownloaded
            )
            coordinator.flow.reconcileStage(
                isTranscriptionSetupReady: refreshedTranscriptionSetupReady,
                enhancementService: enhancementService
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiProviderKeyChanged)) { _ in
            coordinator.flow.refreshAPIVerification()
            coordinator.flow.refreshTranscriptionSetupVerification()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
            guard let action = notification.object as? ShortcutAction,
                  action == coordinator.experienceShortcutAction else {
                return
            }

            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .outputProfilesDidChange)) { _ in
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
        .onChange(of: coordinator.stage) { _, _ in
            coordinator.flow.activateExperienceModeForDemo()
            coordinator.flow.refreshExperienceModeState(enhancementService: enhancementService)
        }
    }

    /// What the summary screen lists: only things the person chose here.
    private var summaryRows: [OnboardingSummaryScreen.Row] {
        let none = String(localized: "Off")
        let speech: String
        switch coordinator.transcriptionSetupKind {
        case .local:
            speech = String(
                format: String(localized: "Local — %@"),
                coordinator.requiredTranscriptionModel?.displayName ?? ""
            )
        case .cloud:
            speech = String(
                format: String(localized: "Cloud — %@"),
                coordinator.selectedOnboardingTranscriptionProvider?.providerKey ?? ""
            )
        }
        let improvement = coordinator.isSelectedAPIProviderVerified
            ? coordinator.selectedOnboardingProvider.rawValue
            : none
        let shortcut = ShortcutStore.shortcut(for: .primaryRecording)?.displayString ?? "—"

        return [
            .init(id: "mic", systemImage: "mic", title: "Microphone", value: coordinator.selectedMicrophoneName ?? "—"),
            .init(id: "speech", systemImage: "captions.bubble", title: "Speech recognition", value: speech),
            .init(id: "improve", systemImage: "wand.and.stars", title: "Text improvement", value: improvement),
            .init(id: "shortcut", systemImage: "keyboard", title: "Recording shortcut", value: shortcut)
        ]
    }

    private func finish(isTranscriptionSetupReady: Bool, showsGuide: Bool) {
        coordinator.flow.completeOnboarding(
            isTranscriptionSetupReady: isTranscriptionSetupReady
        ) {
            hasCompletedOnboardingV2 = true
        }

        if showsGuide {
            // The main window is built once the flag flips; give it time to
            // exist before asking it to present the guide.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                AppTour.show()
            }
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboardingV2: .constant(false))
}
