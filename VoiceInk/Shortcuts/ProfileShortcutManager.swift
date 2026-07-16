import Foundation

/// Owns global per-mode ("profile") shortcuts.
///
/// Since the per-mode shortcut migration (Phase 2), these are finish-only:
/// pressing a mode's shortcut during a live session finishes the current
/// recording and delivers via the mode's own `outputMode`. In .idle it is a
/// no-op — start is always via the shared primary/secondary shortcut.
///
/// The old PTT/hybrid routing through `RecordingShortcutModeHandler` was
/// removed here because it does not apply to finish-only semantics.
@MainActor
class ProfileShortcutManager {
    private let shortcutMonitor = ShortcutMonitor()
    private let finishHandler: @MainActor (UUID) async -> Void
    private var shortcutChangeObserver: NSObjectProtocol?

    init(finishHandler: @escaping @MainActor (UUID) async -> Void) {
        self.finishHandler = finishHandler

        refreshModeShortcuts()

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let action = notification.object as? ShortcutAction,
                case .profile = action
            else {
                return
            }

            Task { @MainActor in
                self?.refreshModeShortcuts()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profileShortcutAvailabilityDidChange),
            name: .profileShortcutAvailabilityDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        MainActor.assumeIsolated {
            shortcutMonitor.stop()
        }
    }

    @objc private func profileShortcutAvailabilityDidChange() {
        Task { @MainActor in
            refreshModeShortcuts()
        }
    }

    private func refreshModeShortcuts() {
        let shortcuts = OutputProfileManager.shared.enabledConfigurations.reduce(into: [ShortcutAction: Shortcut]()) { result, config in
            let action = ShortcutAction.profile(config.id)
            if let shortcut = ShortcutStore.shortcut(for: action) {
                result[action] = shortcut
            }
        }

        shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: [],
            onKeyDown: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self,
                          case .profile(let profileId) = action,
                          self.isValidProfileShortcut(profileId: profileId) else {
                        return
                    }
                    await self.finishHandler(profileId)
                }
            },
            onKeyUp: { _, _ in
                // Finish-only: no PTT, nothing to do on key-up.
            },
            onShortcutInterrupted: { _, _ in
                // Finish-only: no accidental-start guard needed.
            }
        )
    }

    private func isValidProfileShortcut(profileId: UUID) -> Bool {
        guard let config = OutputProfileManager.shared.getConfiguration(with: profileId),
              config.isEnabled,
              ShortcutStore.shortcut(for: .profile(config.id)) != nil else {
            return false
        }
        return true
    }
}
