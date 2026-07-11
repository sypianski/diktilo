import Foundation

/// Holds a one-shot delivery-destination override for the *current* recording
/// session. When the user presses a "finish with …" shortcut while recording
/// (or during transcription / enhancement), the chosen destination is armed
/// here; it overrides the active profile's output mode and trigger-word
/// selection for that single session only.
///
/// Precedence at delivery time is: override > trigger word > profile.
///
/// The override is consumed exactly once — at the moment the delivery
/// configuration is built (`TranscriptionPipeline` just before
/// `TranscriptionDelivery.deliver`). It never mutates the active profile.
@MainActor
final class DeliveryDestinationOverride {
    static let shared = DeliveryDestinationOverride()

    struct Pending {
        let outputMode: OutputMode
        let saveTargetID: UUID?
    }

    private(set) var pending: Pending?

    /// A destination armed *before* a new recording session has actually
    /// started. `VoiceInkEngine.toggleRecord` calls `clear()` synchronously at
    /// the top of the new-session branch to drop any stale override; a plain
    /// `arm()` issued just before that start would therefore be wiped. Global
    /// destination shortcuts that start recording from idle stage the
    /// destination here instead — the *next* `clear()` promotes it into
    /// `pending` rather than discarding it, so the override survives the start
    /// handshake exactly once.
    private var deferredPending: Pending?

    private init() {}

    /// Arm a one-shot override for the current session.
    func arm(outputMode: OutputMode, saveTargetID: UUID? = nil) {
        pending = Pending(outputMode: outputMode, saveTargetID: saveTargetID)
    }

    /// Stage a destination for the recording session that is about to start.
    /// Survives exactly one `clear()` (the one `toggleRecord` fires when it
    /// opens a fresh session), which promotes it into the live `pending`.
    func armForNextSessionStart(outputMode: OutputMode, saveTargetID: UUID? = nil) {
        deferredPending = Pending(outputMode: outputMode, saveTargetID: saveTargetID)
        // Also arm immediately so the override is live if delivery somehow runs
        // before the promoting clear() — promotion below is idempotent.
        pending = Pending(outputMode: outputMode, saveTargetID: saveTargetID)
    }

    /// Return the armed override and clear it. Returns nil when nothing is armed.
    func consume() -> Pending? {
        defer {
            pending = nil
            deferredPending = nil
        }
        return pending
    }

    /// Drop any armed override without consuming it (session start / cancel).
    ///
    /// When a destination was staged via `armForNextSessionStart`, the first
    /// `clear()` promotes it into `pending` instead of wiping it — this is the
    /// `clear()` that `toggleRecord` fires as the new session opens. Subsequent
    /// clears (e.g. cancel) drop everything.
    func clear() {
        if let staged = deferredPending {
            deferredPending = nil
            pending = staged
            return
        }
        pending = nil
    }

    /// Drop everything unconditionally, including a destination staged for the
    /// next session start. Used on cancellation, where no delivery will happen
    /// and a staged destination must not survive into a later session.
    func clearAll() {
        deferredPending = nil
        pending = nil
    }
}
