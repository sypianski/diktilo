import Foundation
import os

/// Speculatively runs AI enhancement on partial transcripts while the user is
/// still speaking, so the final enhancement is instant (cache hit) or at least
/// benefits from a warm connection and provider-side prompt caching.
///
/// Lifecycle: `begin` when a streaming recording starts → `update` on every
/// partial transcript → `consume` from the pipeline with the final text →
/// `cancel` on recording cancel/cleanup.
///
/// Disable with `defaults write com.prakashjoshipax.VoiceInk EnhancementPrewarmEnabled -bool NO`.
@MainActor
final class EnhancementPrewarmService {

    static let enabledDefaultsKey = "EnhancementPrewarmEnabled"

    /// Don't re-enhance for fewer than this many new characters.
    private static let minCharacterDelta = 12
    /// Minimum spacing between speculative requests.
    private static let minInterval: TimeInterval = 2.0

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "EnhancementPrewarmService")
    private let enhancementService: AIEnhancementService

    private var configuration: EnhancementRuntimeConfiguration?
    private var contextSnapshotProvider: (() async -> RecordingContextSnapshot?)?
    /// Mirrors the mechanical post-processing the pipeline applies before
    /// enhancement (filter → trim → paragraph format → word replacement), so
    /// speculative inputs are byte-identical to the pipeline's `textForAI`.
    private var inputTransform: ((String) -> String)?

    private var inFlightTask: Task<Void, Never>?
    private var pendingInput: String?
    private var lastStartedInput = ""
    private var lastStartDate = Date.distantPast
    private var cachedInput = ""
    private var cachedOutput: (text: String, duration: TimeInterval, promptName: String?)?

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil
            || UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    init(enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }

    func begin(
        configuration: EnhancementRuntimeConfiguration,
        inputTransform: @escaping (String) -> String,
        contextSnapshotProvider: @escaping () async -> RecordingContextSnapshot?
    ) {
        reset()
        self.configuration = configuration
        self.inputTransform = inputTransform
        self.contextSnapshotProvider = contextSnapshotProvider
    }

    /// Feed the latest partial transcript. Throttled; at most one request in flight.
    func update(partialText: String) {
        guard isEnabled, let configuration, let inputTransform else { return }

        let input = inputTransform(partialText)
        guard input.count >= Self.minCharacterDelta,
              input != lastStartedInput,
              abs(input.count - lastStartedInput.count) >= Self.minCharacterDelta || input.count < lastStartedInput.count
        else { return }

        if inFlightTask != nil {
            // Remember the newest input; it is picked up when the current request lands.
            pendingInput = input
            return
        }
        if Date().timeIntervalSince(lastStartDate) < Self.minInterval {
            pendingInput = input
            scheduleDrain(after: Self.minInterval)
            return
        }

        start(input: input, configuration: configuration)
    }

    /// Returns the cached enhancement if it matches the final pipeline text exactly.
    func consume(finalText: String) -> (String, TimeInterval, String?)? {
        guard isEnabled else { return nil }
        guard let cachedOutput, cachedInput == finalText else {
            logger.notice("Prewarm miss (cached=\(self.cachedInput.count, privacy: .public) chars, final=\(finalText.count, privacy: .public) chars)")
            return nil
        }
        logger.notice("Prewarm hit — enhancement served from speculative cache")
        return (cachedOutput.text, cachedOutput.duration, cachedOutput.promptName)
    }

    func cancel() {
        reset()
    }

    // MARK: - Private

    private func reset() {
        inFlightTask?.cancel()
        inFlightTask = nil
        pendingInput = nil
        lastStartedInput = ""
        lastStartDate = .distantPast
        cachedInput = ""
        cachedOutput = nil
        configuration = nil
        inputTransform = nil
        contextSnapshotProvider = nil
    }

    private func start(input: String, configuration: EnhancementRuntimeConfiguration) {
        lastStartedInput = input
        lastStartDate = Date()

        inFlightTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.contextSnapshotProvider?()
            guard !Task.isCancelled else { return }

            do {
                let (enhanced, duration, promptName) = try await self.enhancementService.enhance(
                    input,
                    configuration: configuration,
                    contextSnapshot: snapshot
                )
                guard !Task.isCancelled else { return }
                self.cachedInput = input
                self.cachedOutput = (enhanced, duration, promptName)
            } catch {
                // Speculative request — failures are silent; the pipeline's own
                // enhancement call will surface real errors.
                self.logger.info("Prewarm request failed (ignored): \(error.localizedDescription, privacy: .public)")
            }

            self.inFlightTask = nil
            self.drainPending()
        }
    }

    private func scheduleDrain(after delay: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.drainPending()
        }
    }

    private func drainPending() {
        guard inFlightTask == nil,
              let configuration,
              let next = pendingInput,
              next != lastStartedInput
        else { return }
        let elapsed = Date().timeIntervalSince(lastStartDate)
        if elapsed < Self.minInterval {
            scheduleDrain(after: Self.minInterval - elapsed)
            return
        }
        pendingInput = nil
        start(input: next, configuration: configuration)
    }
}
