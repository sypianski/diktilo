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

    private init() {}

    /// Arm a one-shot override for the current session.
    func arm(outputMode: OutputMode, saveTargetID: UUID? = nil) {
        pending = Pending(outputMode: outputMode, saveTargetID: saveTargetID)
    }

    /// Return the armed override and clear it. Returns nil when nothing is armed.
    func consume() -> Pending? {
        defer { pending = nil }
        return pending
    }

    /// Drop any armed override without consuming it (session start / cancel).
    func clear() {
        pending = nil
    }
}
