import SwiftUI

@MainActor
final class OnboardingFlowController {
    private unowned let coordinator: OnboardingCoordinator

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
    }

    func goToTrustStep() {
        coordinator.storedStage = OnboardingStage.trust.rawValue
    }

    func goToPermissionsStep() {
        coordinator.storedStage = OnboardingStage.permissions.rawValue
    }

    func goToModelStep() {
        guard coordinator.requiredPermissionsGranted,
              coordinator.hasSelectedOnboardingMicrophone else { return }
        coordinator.storedStage = OnboardingStage.model.rawValue
    }

    func goToAPIStep(
        isTranscriptionSetupReady: Bool,
        aiService: AIService
    ) {
        guard coordinator.requiredPermissionsGranted,
              coordinator.hasSelectedOnboardingMicrophone,
              isTranscriptionSetupReady else { return }
        ensureDefaultOnboardingProvider()
        selectOnboardingProvider(coordinator.selectedOnboardingProvider, aiService: aiService)
        coordinator.storedStage = OnboardingStage.api.rawValue
    }

    func goBackToModelStep() {
        guard coordinator.requiredPermissionsGranted else {
            goToPermissionsStep()
            return
        }

        coordinator.storedStage = OnboardingStage.model.rawValue
    }

    /// The API step is optional: moving on without a verified key is a skip,
    /// not a warning.
    func continueFromAPIStep(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        if !coordinator.isSelectedAPIProviderVerified {
            coordinator.hasSkippedAPISetup = true
        }
        goToExperienceStep(
            isTranscriptionSetupReady: isTranscriptionSetupReady,
            enhancementService: enhancementService
        )
    }

    func goToExperienceStep(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else { return }
        coordinator.storedStage = OnboardingStage.experience.rawValue
        moveToExperienceStep(0, enhancementService: enhancementService)
    }

    func goToSummaryStep(isTranscriptionSetupReady: Bool) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else { return }
        activateCleanTranscriptionMode()
        coordinator.storedStage = OnboardingStage.summary.rawValue
    }

    func goToPreviousExperienceStep(enhancementService: AIEnhancementService) {
        if coordinator.normalizedExperienceStepIndex > 0 {
            moveToExperienceStep(
                coordinator.normalizedExperienceStepIndex - 1,
                enhancementService: enhancementService
            )
        } else {
            coordinator.storedStage = OnboardingStage.api.rawValue
        }
    }

    func goToPreviousSummaryStep(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else {
            coordinator.storedStage = OnboardingStage.api.rawValue
            return
        }

        let previousIndex = max(coordinator.activeExperienceSteps.count - 1, 0)
        coordinator.storedStage = OnboardingStage.experience.rawValue
        coordinator.experienceStepIndex = previousIndex
        installExperienceMode(at: previousIndex, enhancementService: enhancementService)
        activateExperienceModeForDemo()
        refreshExperienceModeState(enhancementService: enhancementService)
    }

    func advanceExperienceStep(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.isCurrentExperienceReady(isTranscriptionSetupReady: isTranscriptionSetupReady) else {
            return
        }

        if coordinator.isLastExperienceStep {
            goToSummaryStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        } else {
            moveToExperienceStep(
                coordinator.normalizedExperienceStepIndex + 1,
                enhancementService: enhancementService
            )
        }
    }

    func reconcileStage(
        isTranscriptionSetupReady: Bool,
        enhancementService: AIEnhancementService
    ) {
        if coordinator.stage == .model &&
            (!coordinator.requiredPermissionsGranted || !coordinator.hasSelectedOnboardingMicrophone) {
            goToFirstIncompleteSetupStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        }

        if coordinator.stage == .api &&
            (!coordinator.requiredPermissionsGranted ||
             !coordinator.hasSelectedOnboardingMicrophone ||
             !isTranscriptionSetupReady) {
            goToFirstIncompleteSetupStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        }

        if (coordinator.stage == .experience || coordinator.stage == .summary) &&
            !coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) {
            goToFirstIncompleteSetupStep(isTranscriptionSetupReady: isTranscriptionSetupReady)
        }

        if coordinator.stage == .experience &&
            coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) &&
            !coordinator.isExperienceModeInstalled {
            installCurrentExperienceMode(enhancementService: enhancementService)
        }
    }

    func goToFirstIncompleteSetupStep(isTranscriptionSetupReady: Bool) {
        if !coordinator.requiredPermissionsGranted || !coordinator.hasSelectedOnboardingMicrophone {
            coordinator.storedStage = OnboardingStage.permissions.rawValue
        } else if !isTranscriptionSetupReady {
            coordinator.storedStage = OnboardingStage.model.rawValue
        } else {
            coordinator.storedStage = OnboardingStage.api.rawValue
        }
    }

    func downloadTranscriptionModel(
        _ model: FluidAudioModel,
        modelManager: FluidAudioModelManager
    ) {
        guard coordinator.requiredPermissionsGranted,
              coordinator.hasSelectedOnboardingMicrophone,
              !modelManager.isFluidAudioModelDownloaded(model),
              !modelManager.isFluidAudioModelDownloading(model) else {
            return
        }

        Task {
            await modelManager.downloadFluidAudioModel(model)
        }
    }

    func moveToExperienceStep(
        _ index: Int,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.activeExperienceSteps.indices.contains(index) else {
            return
        }

        coordinator.experienceStepIndex = index
        resetExperienceText(at: index)
        installExperienceMode(at: index, enhancementService: enhancementService)
        activateExperienceModeForDemo()
        clearExperienceShortcutForIntroIfNeeded()
        refreshExperienceModeState(enhancementService: enhancementService)
    }

    func completeOnboarding(
        isTranscriptionSetupReady: Bool,
        onComplete: () -> Void
    ) {
        guard coordinator.stage == .summary,
              coordinator.isReadyForExperience(isTranscriptionSetupReady: isTranscriptionSetupReady) else {
            return
        }

        OnboardingStorageKeys.onboardingKeys.forEach {
            coordinator.defaults.removeObject(forKey: $0)
        }
        DefaultModeSeeder.seedIfEmpty()
        activateCleanTranscriptionMode()
        onComplete()
    }

    func refreshAPIVerification() {
        coordinator.isSelectedAPIProviderVerified = APIKeyManager.shared.hasAPIKey(
            forProvider: coordinator.selectedOnboardingProvider.rawValue
        )

        if coordinator.isSelectedAPIProviderVerified {
            coordinator.hasSkippedAPISetup = false
        }
    }

    func refreshTranscriptionSetupVerification() {
        ensureDefaultOnboardingTranscriptionProvider()

        guard let provider = coordinator.selectedOnboardingTranscriptionProvider else {
            coordinator.isSelectedTranscriptionProviderVerified = false
            return
        }

        coordinator.isSelectedTranscriptionProviderVerified = APIKeyManager.shared.hasAPIKey(
            forProvider: provider.providerKey
        )
    }

    func selectOnboardingTranscriptionSetup(_ kind: OnboardingTranscriptionSetupKind) {
        coordinator.storedTranscriptionSetupKind = kind.rawValue
        ensureDefaultOnboardingTranscriptionProvider()
        refreshTranscriptionSetupVerification()
    }

    func ensureDefaultOnboardingTranscriptionProvider() {
        let options = coordinator.onboardingTranscriptionProviderOptions
        if options.contains(where: {
            $0.providerKey.caseInsensitiveCompare(coordinator.storedOnboardingTranscriptionProvider) == .orderedSame
        }) {
            return
        }

        let defaultProvider = coordinator.recommendedOnboardingTranscriptionProvider ?? options.first
        coordinator.storedOnboardingTranscriptionProvider = defaultProvider?.providerKey ?? ""
    }

    func selectOnboardingTranscriptionProvider(_ providerKey: String) {
        guard coordinator.onboardingTranscriptionProviderOptions.contains(where: {
            $0.providerKey.caseInsensitiveCompare(providerKey) == .orderedSame
        }) else { return }

        coordinator.storedOnboardingTranscriptionProvider = providerKey
        refreshTranscriptionSetupVerification()
    }

    func ensureDefaultOnboardingProvider() {
        if let storedProvider = AIProvider(rawValue: coordinator.storedOnboardingAIProvider),
           coordinator.onboardingProviderOptions.contains(storedProvider) {
            return
        }

        let defaultProvider: AIProvider = coordinator.onboardingProviderOptions.contains(.groq)
            ? .groq
            : coordinator.onboardingProviderOptions.first ?? .groq
        coordinator.storedOnboardingAIProvider = defaultProvider.rawValue
    }

    func selectOnboardingProvider(_ provider: AIProvider, aiService: AIService) {
        guard coordinator.onboardingProviderOptions.contains(provider) else { return }

        coordinator.storedOnboardingAIProvider = provider.rawValue

        if APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue) {
            aiService.selectedProvider = provider
            aiService.selectModel(provider.defaultModel, for: provider)
        }

        refreshAPIVerification()
    }

    func installExperienceMode(
        at index: Int,
        enhancementService: AIEnhancementService
    ) {
        guard coordinator.activeExperienceSteps.indices.contains(index) else {
            return
        }

        var seenKinds = Set<StarterModeKind>()
        let installedKinds = coordinator.activeExperienceSteps
            .prefix(index + 1)
            .map(\.starterModeKind)
            .filter { seenKinds.insert($0).inserted }

        let installedSteps = Array(coordinator.activeExperienceSteps.prefix(index + 1))

        let seedResult = StarterModePromptSeeder.ensurePrompts(
            for: installedKinds,
            in: enhancementService.customPrompts
        )
        if seedResult.didChange {
            enhancementService.customPrompts = seedResult.prompts
        }

        StarterModeFactory.install(
            kinds: installedKinds,
            provider: coordinator.selectedOnboardingProvider,
            modelName: coordinator.selectedOnboardingProvider.defaultModel,
            transcriptionModelName: coordinator.selectedOnboardingTranscriptionModelName
                ?? StarterModeFactory.defaultTranscriptionModelName,
            isRealtimeTranscriptionEnabled: coordinator.selectedOnboardingTranscriptionUsesRealtime,
            selectedLanguage: coordinator.selectedOnboardingTranscriptionLanguage
        )

        removeModeShortcutStorageForPrimaryRecordingSteps(installedSteps)
        applyDefaultMode(for: coordinator.activeExperienceSteps[index])
    }

    func installCurrentExperienceMode(enhancementService: AIEnhancementService) {
        guard coordinator.stage == .experience else { return }
        installExperienceMode(
            at: coordinator.normalizedExperienceStepIndex,
            enhancementService: enhancementService
        )
        refreshExperienceModeState(enhancementService: enhancementService)
    }

    func refreshExperienceModeState(enhancementService: AIEnhancementService) {
        let hasRequiredPrompts = StarterModePromptSeeder.hasPrompts(
            for: [coordinator.experienceModeTemplate.kind],
            in: enhancementService.customPrompts
        )

        coordinator.isExperienceModeInstalled =
            StarterModeFactory.isInstalled(kind: coordinator.experienceModeTemplate.kind) &&
            hasRequiredPrompts
        coordinator.hasExperienceModeShortcut = ShortcutStore.shortcut(for: coordinator.experienceShortcutAction) != nil
    }

    func clearExperienceShortcutForIntroIfNeeded() {
        guard coordinator.stage == .experience,
              coordinator.experienceStep.shouldClearShortcutOnIntro,
              !coordinator.clearedExperienceShortcutActions.contains(coordinator.experienceShortcutAction) else {
            return
        }

        var clearedActions = coordinator.clearedExperienceShortcutActions
        clearedActions.insert(coordinator.experienceShortcutAction)
        coordinator.clearedExperienceShortcutActions = clearedActions
        ShortcutStore.setShortcut(nil, for: coordinator.experienceShortcutAction)
    }

    func activateExperienceModeForDemo() {
        guard coordinator.stage == .experience,
              let config = OutputProfileManager.shared.getConfiguration(with: coordinator.experienceModeTemplate.id) else {
            return
        }

        applyDefaultMode(for: coordinator.experienceStep)
        OutputProfileManager.shared.setActiveConfiguration(config)
    }

    func activateCleanTranscriptionMode() {
        guard let cleanTemplate = StarterModeCatalog.templates.first(where: { $0.kind == .clean }),
              let cleanConfig = OutputProfileManager.shared.getConfiguration(with: cleanTemplate.id) else {
            return
        }

        OutputProfileManager.shared.setAsDefault(configId: cleanConfig.id)
        OutputProfileManager.shared.setActiveConfiguration(cleanConfig)
    }

    private func applyDefaultMode(for step: OnboardingExperienceStep) {
        setDefaultStarterMode(step.defaultModeKind)
    }

    private func setDefaultStarterMode(_ kind: StarterModeKind) {
        guard let template = StarterModeCatalog.templates.first(where: { $0.kind == kind }),
              OutputProfileManager.shared.getConfiguration(with: template.id) != nil,
              OutputProfileManager.shared.getDefaultConfiguration()?.id != template.id else {
            return
        }

        OutputProfileManager.shared.setAsDefault(configId: template.id)
    }

    private func removeModeShortcutStorageForPrimaryRecordingSteps(_ steps: [OnboardingExperienceStep]) {
        var removedTemplateIds = Set<UUID>()

        for step in steps where step.usesPrimaryRecordingShortcut {
            let template = modeTemplate(for: step)
            guard removedTemplateIds.insert(template.id).inserted else {
                continue
            }

            let action = ShortcutAction.profile(template.id)
            if ShortcutStore.rawShortcut(for: action) != nil || ShortcutStore.isShortcutCleared(for: action) {
                ShortcutStore.removeShortcutStorage(for: action)
            }
        }
    }

    private func modeTemplate(for step: OnboardingExperienceStep) -> StarterModeTemplate {
        StarterModeCatalog.templates.first { $0.kind == step.starterModeKind } ?? StarterModeCatalog.templates[0]
    }

    func resetExperienceText(at index: Int) {
        guard coordinator.activeExperienceSteps.indices.contains(index) else {
            return
        }

        let step = coordinator.activeExperienceSteps[index]
        var updatedText = coordinator.experienceTextByKind
        updatedText[step.kind] = step.initialFieldText
        coordinator.experienceTextByKind = updatedText
    }
}
