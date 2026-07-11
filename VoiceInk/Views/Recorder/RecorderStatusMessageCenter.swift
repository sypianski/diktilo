import SwiftUI

// MARK: - RecorderStatusMessageCenter

/// Singleton that owns the transient status message shown inside the
/// recorder HUD strip (28 pt band shared with RecorderDestinationHUDView).
/// Any code running on @MainActor can call `show(_:icon:text:duration:)`;
/// the message auto-clears after the duration elapses.  A new `show` call
/// cancels the pending auto-clear and starts a fresh timer.
@MainActor
final class RecorderStatusMessageCenter: ObservableObject {
    static let shared = RecorderStatusMessageCenter()

    enum Kind {
        case info
        case success
        case warning
    }

    struct Message: Equatable {
        let kind: Kind
        let icon: String
        let text: String
    }

    @Published private(set) var current: Message?

    private var autoClearTask: Task<Void, Never>?

    private init() {}

    /// Display `text` with a leading SF Symbol `icon` for at most `duration` seconds.
    /// Calling again while a message is visible cancels the previous auto-clear timer.
    func show(_ kind: Kind, icon: String, text: String, duration: TimeInterval = 1.8) {
        autoClearTask?.cancel()
        current = Message(kind: kind, icon: icon, text: text)
        let d = duration
        autoClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func clear() {
        autoClearTask?.cancel()
        autoClearTask = nil
        current = nil
    }
}

// MARK: - RecorderStatusMessageView

/// Renders a single status message as a capsule fitting the 28 pt HUD band.
struct RecorderStatusMessageView: View {
    let message: RecorderStatusMessageCenter.Message

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: message.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(iconColor)

            Text(message.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(strokeColor, lineWidth: 0.5)
                )
        )
        .frame(height: 28)
    }

    private var iconColor: Color {
        switch message.kind {
        case .info:    return .secondary
        case .success: return Color.green
        case .warning: return Color.orange
        }
    }

    private var strokeColor: Color {
        switch message.kind {
        case .info:    return Color.white.opacity(0.18)
        case .success: return Color.green.opacity(0.45)
        case .warning: return Color.orange.opacity(0.5)
        }
    }
}
