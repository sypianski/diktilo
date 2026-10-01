import Foundation
import SwiftData
import os

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → AI enhance → deliver → save
@MainActor
class TranscriptionPipeline {
    struct AssistantHooks {
        let isFollowUp: Bool
        let sendFollowUp: (String, Transcription) async -> Void
        let startResponse: (String, EnhancementRuntimeConfiguration) async -> Void
        let showResponse: (String, String?) async -> Void
        let failResponse: (String) async -> Void

        static let inactive = AssistantHooks(
            isFollowUp: false,
            sendFollowUp: { _, _ in },
            startResponse: { _, _ in },
            showResponse: { _, _ in },
            failResponse: { _ in }
        )
    }

    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let delivery = TranscriptionDelivery()
    /// Offered on the failure notification; set by the engine, which owns the
    /// managers the retry needs.
    var retryLastTranscription: (() -> Void)?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionPipeline")

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry,
        enhancementService: AIEnhancementService?
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
        self.enhancementService = enhancementService
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - audioURL: The recorded audio file.
    ///   - transcriptionConfiguration: Mode-resolved transcription engine settings for this phase.
    ///   - session: An active streaming session if one was prepared, otherwise nil.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCancel: Called when cancellation is detected to cancel active session state.
    ///   - onDismiss: Called when delivery should close the recorder panel.
    func run(
        transcription: Transcription,
        audioURL: URL,
        transcriptionConfiguration: TranscriptionRuntimeConfiguration,
        formattingConfiguration resolveFormattingConfiguration: @escaping () -> TranscriptionFormattingConfiguration,
        session: TranscriptionSession?,
        triggerWordModeSelection: @escaping (String) -> String? = { _ in nil },
        enhancementConfiguration: @escaping () -> EnhancementRuntimeConfiguration?,
        prewarmedEnhancement: @escaping (String) -> (String, TimeInterval, String?)? = { _ in nil },
        recordingContextSnapshot: @escaping () async -> RecordingContextSnapshot? = { nil },
        outputConfiguration: @escaping () -> OutputRuntimeConfiguration,
        onStateChange: @escaping (RecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void,
        assistant: AssistantHooks = .inactive
    ) async {
        let model = transcriptionConfiguration.model
        // The model that actually produced the text (a fallback when `model` failed).
        var usedModel: any TranscriptionModel = model
        var finalText: String?
        var didInsertSessionMetric = false
        var responseError: String?
        var outputForDelivery: OutputRuntimeConfiguration?
        var responseConfig: EnhancementRuntimeConfiguration?

        func finishCanceledTranscription() async {
            await onCancel()

            let canceledDuration: TimeInterval?
            if transcription.duration > 0 {
                canceledDuration = nil
            } else {
                let duration = await AudioFileMetadata.duration(for: audioURL)
                canceledDuration = duration > 0 ? duration : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? model.displayName
            )

            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save canceled transcription: \(error, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        do {
            let transcriptionStart = Date()
            var text: String
            do {
                if let session {
                    text = try await session.transcribe(audioURL: audioURL)
                } else {
                    text = try await serviceRegistry.transcribe(
                        audioURL: audioURL,
                        model: model,
                        context: transcriptionConfiguration.requestContext
                    )
                }
            } catch {
                if error is CancellationError || shouldCancel() { throw error }
                let fallback = try await transcribeWithFallbacks(
                    audioURL: audioURL,
                    configuration: transcriptionConfiguration,
                    firstFailure: error,
                    shouldCancel: shouldCancel
                )
                text = fallback.text
                usedModel = fallback.model
            }
            text = TranscriptionOutputFilter.filter(text)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            if shouldCancel() { await finishCanceledTranscription(); return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !assistant.isFollowUp,
               let processedText = triggerWordModeSelection(text) {
                text = processedText
            }

            let formattingConfiguration = resolveFormattingConfiguration()
            let resolvedEnhancementConfiguration = enhancementConfiguration()
            let resolvedOutputConfiguration = outputConfiguration()
            let modeMetadata = metadata(
                for: formattingConfiguration.profile ??
                    resolvedEnhancementConfiguration?.profile ??
                    resolvedOutputConfiguration.profile ??
                    transcriptionConfiguration.profile
            )

            if formattingConfiguration.isTextFormattingEnabled {
                text = ParagraphFormatter.format(text)
            }

            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            let cleanedText = text

            let actualDuration = await AudioFileMetadata.duration(for: audioURL)

            transcription.text = cleanedText
            transcription.duration = actualDuration
            transcription.transcriptionModelName = usedModel.displayName
            transcription.transcriptionDuration = transcriptionDuration
            transcription.modeName = modeMetadata.name
            transcription.modeEmoji = modeMetadata.emoji
            finalText = cleanedText

            if !assistant.isFollowUp {
                let shouldRespondInRecorder = resolvedOutputConfiguration.outputMode == .respond &&
                    resolvedEnhancementConfiguration?.isEnabled == true &&
                    resolvedEnhancementConfiguration.map { configuration in
                        enhancementService?.isConfigured(for: configuration) == true
                    } == true
                outputForDelivery = resolvedOutputConfiguration
                responseConfig = shouldRespondInRecorder ? resolvedEnhancementConfiguration : nil

                let isSkipShortEnhancementEnabled = UserDefaults.standard.bool(forKey: "SkipShortEnhancement")
                let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
                let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
                let shouldSkipEnhancement = !shouldRespondInRecorder &&
                    isSkipShortEnhancementEnabled &&
                    WordCounter.count(in: text) <= shortEnhancementWordThreshold

                if let enhancementService,
                   let resolvedEnhancementConfiguration,
                   resolvedEnhancementConfiguration.isEnabled,
                   enhancementService.isConfigured(for: resolvedEnhancementConfiguration),
                   !shouldSkipEnhancement {
                    if shouldCancel() { await finishCanceledTranscription(); return }

                    onStateChange(.enhancing)
                    let textForAI = text
                    if shouldRespondInRecorder {
                        await assistant.startResponse(textForAI, resolvedEnhancementConfiguration)
                    }

                    do {
                        let enhancedText: String
                        let enhancementDuration: TimeInterval
                        let promptName: String?
                        // The mode's model, or the fallback that answered instead.
                        var usedEnhancementConfiguration = resolvedEnhancementConfiguration
                        if let prewarmed = prewarmedEnhancement(textForAI) {
                            (enhancedText, enhancementDuration, promptName) = prewarmed
                        } else {
                            let contextSnapshot = await recordingContextSnapshot()
                            let outcome = try await enhancementService.enhanceWithFallbacks(
                                textForAI,
                                configuration: resolvedEnhancementConfiguration,
                                contextSnapshot: contextSnapshot
                            )
                            (enhancedText, enhancementDuration, promptName) = (outcome.text, outcome.duration, outcome.promptName)
                            usedEnhancementConfiguration = outcome.configuration
                        }
                        transcription.enhancedText = enhancedText
                        transcription.aiEnhancementModelName = usedEnhancementConfiguration.modelName ?? usedEnhancementConfiguration.provider?.defaultModel
                        transcription.promptName = promptName
                        transcription.enhancementDuration = enhancementDuration
                        transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                        transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                        finalText = enhancedText
                    } catch {
                        let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        transcription.enhancedText = String(format: String(localized: "Enhancement failed: %@"), errorDescription)
                        responseError = errorDescription
                        let shortReason = String(errorDescription.prefix(160))
                        await MainActor.run {
                            NotificationManager.shared.showNotification(
                                title: String(format: String(localized: "Enhancement failed: %@"), shortReason),
                                type: .warning
                            )
                        }
                        if shouldCancel() { await finishCanceledTranscription(); return }
                    }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

            if let nativeAppleError = error as? NativeAppleTranscriptionService.ServiceError,
               nativeAppleError.shouldShowNotification {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: errorDescription,
                        type: .error,
                        duration: 5.0
                    )
                }
            } else if !shouldCancel() {
                // Every model of the chain failed: say so instead of closing the
                // panel silently. The recording stays in History.
                NotificationManager.shared.showNotification(
                    title: String(format: String(localized: "Transcription failed: %@"), String(errorDescription.prefix(160))),
                    type: .error,
                    duration: 8.0,
                    actionButton: retryLastTranscription.map { (label: String(localized: "Transcribe Again"), action: $0) }
                )
            }

            transcription.text = String(format: String(localized: "Transcription Failed: %@"), errorDescription)
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        func saveTranscriptionAndPostCompletion() {
            if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                do {
                    didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                        transcription: transcription,
                        model: usedModel,
                        in: modelContext
                    )
                } catch {
                    logger.error("Failed to record session metric: \(error, privacy: .public)")
                }
            }

            do {
                try modelContext.save()
                if didInsertSessionMetric {
                    NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
                }
                NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
            } catch {
                logger.error("Failed to save transcription: \(error, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        // Resolve the delivery destination as late as possible so a one-shot
        // override armed during .transcribing / .enhancing (via a "finish
        // with …" shortcut) still wins. Precedence: override > trigger word
        // (already applied above) > profile.
        var deliveryOutput = outputForDelivery ?? outputConfiguration()
        var deliveryResponseConfig = responseConfig
        if !assistant.isFollowUp, let override = DeliveryDestinationOverride.shared.consume() {
            deliveryOutput = OutputRuntimeConfiguration(
                profile: deliveryOutput.profile,
                outputMode: override.outputMode,
                autoSendKey: deliveryOutput.autoSendKey,
                customCommand: deliveryOutput.customCommand,
                saveTargetID: override.saveTargetID ?? deliveryOutput.saveTargetID
            )
            // Override destinations are never .respond, so drop any pending
            // in-recorder response so the delivery routes to the new mode.
            deliveryResponseConfig = nil
        } else if assistant.isFollowUp {
            // Follow-up sessions always deliver via the assistant path; drain
            // any override armed mid-session so it cannot linger as state.
            DeliveryDestinationOverride.shared.clear()
        }

        await delivery.deliver(
            TranscriptionDelivery.Request(
                transcription: transcription,
                text: finalText,
                output: deliveryOutput,
                responseConfig: deliveryResponseConfig,
                responseError: responseError,
                isAssistantFollowUp: assistant.isFollowUp
            ),
            actions: TranscriptionDelivery.Actions(
                setState: onStateChange,
                dismiss: onDismiss,
                sendFollowUp: assistant.sendFollowUp,
                showResponse: assistant.showResponse,
                failResponse: assistant.failResponse
            )
        )

        saveTranscriptionAndPostCompletion()
    }

    /// Tries the usable models after the main one, in fallback-chain order.
    private func transcribeWithFallbacks(
        audioURL: URL,
        configuration: TranscriptionRuntimeConfiguration,
        firstFailure: Error,
        shouldCancel: () -> Bool
    ) async throws -> (text: String, model: any TranscriptionModel) {
        guard !configuration.fallbackModels.isEmpty else { throw firstFailure }

        var attempts = [ModelChainError.Attempt(
            name: configuration.model.displayName,
            reason: ModelChainError.reason(for: firstFailure)
        )]
        logger.warning("Transcription with \(configuration.model.name, privacy: .public) failed, trying fallbacks: \(firstFailure, privacy: .public)")

        for fallback in configuration.fallbackModels {
            if shouldCancel() { throw CancellationError() }
            do {
                let text = try await serviceRegistry.transcribe(
                    audioURL: audioURL,
                    model: fallback,
                    context: configuration.requestContext(forFallback: fallback)
                )
                logger.notice("Transcribed with fallback model \(fallback.name, privacy: .public)")
                return (text: text, model: fallback)
            } catch {
                if error is CancellationError { throw error }
                logger.warning("Fallback \(fallback.name, privacy: .public) failed: \(error, privacy: .public)")
                attempts.append(.init(name: fallback.displayName, reason: ModelChainError.reason(for: error)))
            }
        }

        throw ModelChainError(attempts: attempts)
    }

    private func metadata(for mode: OutputProfile?) -> (name: String?, emoji: String?) {
        guard let mode, mode.isEnabled else {
            return (nil, nil)
        }

        return (mode.name, mode.icon.value)
    }
}
