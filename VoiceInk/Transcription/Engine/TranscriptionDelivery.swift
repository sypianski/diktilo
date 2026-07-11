import Foundation
import os

@MainActor
final class TranscriptionDelivery {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionDelivery")

    struct Request {
        let transcription: Transcription
        let text: String?
        let output: OutputRuntimeConfiguration
        let responseConfig: EnhancementRuntimeConfiguration?
        let responseError: String?
        let isAssistantFollowUp: Bool
    }

    struct Actions {
        let setState: (RecordingState) -> Void
        let dismiss: () async -> Void
        let sendFollowUp: (String, Transcription) async -> Void
        let showResponse: (String, String?) async -> Void
        let failResponse: (String) async -> Void
    }

    func deliver(_ request: Request, actions: Actions) async {
        guard request.transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue else {
            await actions.dismiss()
            return
        }

        if request.isAssistantFollowUp {
            await deliverFollowUp(request, actions: actions)
            return
        }

        if request.output.outputMode == .respond,
           request.responseConfig != nil || request.responseError != nil {
            await deliverResponse(request, actions: actions)
            return
        }

        if request.output.outputMode == .customCommand {
            await deliverCustomCommand(request, actions: actions)
            return
        }

        if request.output.outputMode == .saveTarget {
            await deliverSaveTarget(request, actions: actions)
            return
        }

        if request.output.outputMode == .copy {
            await deliverCopy(request, actions: actions)
            return
        }

        if request.output.outputMode == .editWindow {
            await deliverEditWindow(request, actions: actions)
            return
        }

        if let text = request.text {
            await paste(text, output: request.output, actions: actions)
        } else {
            await actions.dismiss()
        }
    }

    private func deliverFollowUp(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        actions.setState(.enhancing)
        await actions.sendFollowUp(text, item.transcription)
    }

    private func deliverCopy(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        if let text = item.text, !ClipboardManager.setClipboard(deliverableText(from: text)) {
            logger.error("Failed to copy transcription to clipboard")
        }

        await actions.dismiss()
    }

    private func deliverEditWindow(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        guard let text = item.text else { return }
        TranscriptEditManager.shared.present(text: deliverableText(from: text))
    }

    private func deliverResponse(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        if let responseError = item.responseError {
            await actions.failResponse("Enhancement failed: \(responseError)")
        } else if let text = item.text,
                  item.responseConfig != nil {
            await actions.showResponse(text, item.transcription.aiRequestSystemMessage)
        } else {
            await actions.failResponse("No response was generated.")
        }
    }

    private func deliverCustomCommand(_ item: Request, actions: Actions) async {
        guard let text = item.text else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.noTextToDeliver)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        guard let customCommand = item.output.customCommand,
              let command = customCommand.trimmedCommand else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.commandNotConfigured)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        let commandText = deliverableText(from: text)
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        Task {
            await runCustomCommand(command: command, commandText: commandText)
        }
    }

    private func deliverSaveTarget(_ item: Request, actions: Actions) async {
        let center = RecorderStatusMessageCenter.shared

        // Pick text the same way deliverCopy does.
        let textToSave = item.text.map { deliverableText(from: $0) }

        guard let text = textToSave else {
            // Nothing to save — tell the user inside the panel, then dismiss.
            center.show(.warning, icon: "exclamationmark.triangle.fill",
                        text: String(localized: "No transcription text — nothing to save."), duration: 2.2)
            SoundManager.shared.playStopSound()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await actions.dismiss()
            return
        }

        guard let targetID = item.output.saveTargetID,
              let target = SaveTargetManager.shared.target(withID: targetID) else {
            // No target configured — fall back to clipboard, tell user.
            if !ClipboardManager.setClipboard(text) {
                logger.error("Save target not configured and clipboard copy also failed")
            }
            center.show(.warning, icon: "exclamationmark.triangle.fill",
                        text: String(localized: "Save target not configured — copied to clipboard."), duration: 2.2)
            SoundManager.shared.playStopSound()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await actions.dismiss()
            return
        }

        // Safety net: clipboard first so text survives even a forced quit.
        if !ClipboardManager.setClipboard(text) {
            logger.error("Pre-save clipboard safety copy failed")
        }

        SoundManager.shared.playStopSound()

        // Race delivery against a 1.5 s timeout.
        // Pattern: unstructured Task for delivery (never cancelled by the race),
        // CheckedContinuation to relay the first result to the racing code, and
        // a separate background observer Task for the post-timeout notification path.
        //
        // Three outcomes:
        //   success   — delivery done within 1.5 s, no error
        //   failure   — delivery done within 1.5 s, threw an error
        //   timedOut  — delivery still running; panel closes, system notification fires later

        enum DeliveryOutcome {
            case success(String)
            case failure(String)
            case timedOut
        }

        // Shared atomic flag: true once the continuation has been resumed (either by
        // delivery or by the timeout). Prevents double-resume.
        final class Once: @unchecked Sendable {
            var fired = false
        }
        let once = Once()
        let lock = NSLock()

        // Race result delivered through a continuation.
        let raceOutcome: DeliveryOutcome = await withCheckedContinuation { continuation in
            // Timeout arm — resumes with .timedOut if delivery is still pending.
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                lock.lock()
                guard !once.fired else { lock.unlock(); return }
                once.fired = true
                lock.unlock()
                continuation.resume(returning: .timedOut)
            }

            // Delivery arm — unstructured so it outlives the continuation.
            Task {
                do {
                    let description = try await SaveTargetDeliveryService.deliver(text: text, target: target)
                    lock.lock()
                    let shouldResume = !once.fired
                    once.fired = true
                    lock.unlock()
                    if shouldResume {
                        timeoutTask.cancel()
                        continuation.resume(returning: .success(description))
                    } else {
                        // Timed out already — panel dismissed; post system notification.
                        await MainActor.run {
                            NotificationManager.shared.showNotification(
                                title: String(format: String(localized: "Saved to %@"), target.name),
                                type: .success
                            )
                            logger.notice("Save target delivery succeeded (after timeout): \(description, privacy: .public)")
                        }
                    }
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    lock.lock()
                    let shouldResume = !once.fired
                    once.fired = true
                    lock.unlock()
                    if shouldResume {
                        timeoutTask.cancel()
                        continuation.resume(returning: .failure(msg))
                    } else {
                        await MainActor.run {
                            _ = ClipboardManager.setClipboard(text)
                            NotificationManager.shared.showNotification(
                                title: String(format: String(localized: "Save failed (%@) — copied to clipboard."), msg),
                                type: .error
                            )
                            logger.error("Save target delivery failed (after timeout): \(msg, privacy: .public)")
                        }
                    }
                }
            }
        }

        switch raceOutcome {
        case .success(let description):
            center.show(.success, icon: "checkmark.circle.fill",
                        text: String(format: String(localized: "Copied — sent to %@"), target.name),
                        duration: 1.6)
            logger.notice("Save target delivery succeeded: \(description, privacy: .public)")
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await actions.dismiss()

        case .failure(let message):
            center.show(.warning, icon: "exclamationmark.triangle.fill",
                        text: String(localized: "Send failed — copied to clipboard"),
                        duration: 2.2)
            logger.error("Save target delivery failed: \(message, privacy: .public)")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await actions.dismiss()

        case .timedOut:
            center.show(.info, icon: target.icon,
                        text: String(format: String(localized: "Sending to %@… (copied)"), target.name),
                        duration: 2.0)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await actions.dismiss()
            // Delivery task is still running in background and will post a system
            // notification via the else-branch above when it eventually completes.
        }
    }

    private func runCustomCommand(command: String, commandText: String) async {
        let startTime = Date()
        logger.notice("Custom command started")

        do {
            let result = try await CustomCommandDeliveryRunner.run(
                command: command,
                timeout: 10,
                context: CustomCommandDeliveryContext(transcript: commandText)
            )

            let duration = Date().timeIntervalSince(startTime)
            let stdoutBytes = result.stdout.utf8.count
            let stderrBytes = result.stderr.utf8.count

            if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.notice("Custom command stdout bytes=\(stdoutBytes, privacy: .public): \(result.stdout, privacy: .public)")
            }

            if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.notice(
                    "Custom command succeeded with stderr duration=\(Self.formattedDuration(duration), privacy: .public)s stdoutBytes=\(stdoutBytes, privacy: .public) stderrBytes=\(stderrBytes, privacy: .public): \(result.stderr, privacy: .public)"
                )
            } else {
                logger.notice(
                    "Custom command succeeded duration=\(Self.formattedDuration(duration), privacy: .public)s stdoutBytes=\(stdoutBytes, privacy: .public) stderrBytes=\(stderrBytes, privacy: .public)"
                )
            }
        } catch {
            notifyCustomCommandFailure(error, duration: Date().timeIntervalSince(startTime))
        }
    }

    private func notifyCustomCommandFailure(_ error: Error, duration: TimeInterval? = nil) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let duration {
            logger.error("Custom command failed duration=\(Self.formattedDuration(duration), privacy: .public)s: \(message, privacy: .public)")
        } else {
            logger.error("Custom command failed: \(message, privacy: .public)")
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        String(format: "%.3f", duration)
    }

    private func paste(_ text: String, output: OutputRuntimeConfiguration, actions: Actions) async {
        let textToPaste = deliverableText(from: text)
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let pastedText = textToPaste + (appendSpace ? " " : "")
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        let pasteTask = CursorPaster.startPasteAtCursor(pastedText)

        let autoSendKey = output.outputMode == .paste ? output.autoSendKey : .none
        Task { @MainActor in
            _ = await pasteTask.value

            if autoSendKey.isEnabled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                CursorPaster.performAutoSend(autoSendKey)
            }
        }
    }

    private func deliverableText(from text: String) -> String {
        var textToDeliver = text
        if let restrictionMessage = LicenseViewModel().usageRestrictionMessage {
            textToDeliver = """
                \(restrictionMessage)
                \n\(textToDeliver)
                """
        }

        return textToDeliver
    }
}
