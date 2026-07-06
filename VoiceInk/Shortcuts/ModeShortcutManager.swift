import Foundation

@MainActor
class ProfileShortcutManager {
    private let shortcutMonitor = ShortcutMonitor()
    private let modeProvider: @MainActor () -> RecordingShortcutManager.Mode
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private var shortcutChangeObserver: NSObjectProtocol?

    init(
        modeProvider: @escaping @MainActor () -> RecordingShortcutManager.Mode,
        shortcutModeHandler: RecordingShortcutModeHandler
    ) {
        self.modeProvider = modeProvider
        self.shortcutModeHandler = shortcutModeHandler

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
            interruptibleActions: Set(shortcuts.keys),
            onKeyDown: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                          let profileId = self.profileId(for: action) else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        profileId: profileId
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self,
                          case .profile(let profileId) = action else {
                        return
                    }

                    await self.shortcutModeHandler.handleKeyUp(
                        action: action,
                        eventTime: eventTime,
                        mode: self.modeProvider(),
                        profileId: profileId
                    )
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, case .profile = action else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )
    }

    private func profileId(for action: ShortcutAction) -> UUID? {
        guard case .profile(let profileId) = action,
              let config = OutputProfileManager.shared.getConfiguration(with: profileId),
              config.isEnabled,
              ShortcutStore.shortcut(for: .profile(config.id)) != nil else {
            return nil
        }

        return profileId
    }
}
