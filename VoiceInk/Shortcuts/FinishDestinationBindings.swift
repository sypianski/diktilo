import Foundation
import Carbon.HIToolbox

// MARK: - Shared finish-destination binding helpers
//
// After the per-mode finish refactor:
//   • The three fixed destinations (Copy / Paste / Edit Window) no longer own
//     global shortcuts — LegacyFinishShortcutMigration reattached any user
//     binding to a per-mode `.profile(id)` shortcut and cleared the legacy
//     slot. `effectiveShortcut` is kept only so the migration can still read
//     the pre-migration value.
//   • Save-target finishers stay global (`.finishWithSaveTarget(id)`).
//   • The recorder HUD lists both save-target finishers AND enabled modes with
//     a `.profile(id)` shortcut.

enum FinishDestinationBindings {

    // MARK: - Effective shortcut for a legacy fixed destination
    //
    // Preserved for LegacyFinishShortcutMigration only. Returns:
    //   • explicit user binding if set
    //   • nil if the user cleared it (or the migration cleared it)
    //   • no fallback anymore — the ⌃⌥C/V/E defaults are gone.

    static func effectiveShortcut(for action: ShortcutAction) -> Shortcut? {
        if let stored = ShortcutStore.shortcut(for: action) {
            return stored
        }
        if ShortcutStore.isShortcutCleared(for: action) {
            return nil
        }
        // Legacy fallback kept in-line so we don't hold a table of dead cases.
        // Only fires during the one-shot migration window, then never again.
        switch action {
        case .finishWithCopy:       return .key(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.control, .option])
        case .finishWithPaste:      return .key(keyCode: UInt16(kVK_ANSI_V), modifierFlags: [.control, .option])
        case .finishWithEditWindow: return .key(keyCode: UInt16(kVK_ANSI_E), modifierFlags: [.control, .option])
        default:                    return nil
        }
    }

    // MARK: - Default per-target bindings

    /// Gives a freshly created Notaro preset target a working shortcut out of
    /// the box. No-op when the user already bound or deliberately cleared one,
    /// or when Ctrl+Option+N fails validation (e.g. collides with another
    /// binding). Ctrl+Option (not plain Option) avoids the ń dead key on the
    /// Polish Pro layout.
    static func assignDefaultNotaroShortcut(targetID: UUID) {
        let action = ShortcutAction.finishWithSaveTarget(targetID)
        guard ShortcutStore.shortcut(for: action) == nil,
              !ShortcutStore.isShortcutCleared(for: action) else { return }
        ShortcutStore.setShortcut(
            .key(keyCode: UInt16(kVK_ANSI_N), modifierFlags: [.control, .option]),
            for: action
        )
    }

    // MARK: - HUD item model

    struct HUDItem: Identifiable {
        var id: String          // stable — action storageName or target UUID string
        var icon: String        // SF Symbol name
        var label: String       // short human label
        var shortcutDisplay: String  // e.g. "⌥C"
    }

    // MARK: - Build the list shown by the HUD

    /// Returns HUD chips for every visible finish shortcut:
    ///   • enabled modes with a `.profile(id)` shortcut bound
    ///   • save targets with an explicit binding
    /// plus a fixed `⌘↩` chip for the panel-scoped finish.
    @MainActor
    static func hudItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Per-mode finish shortcuts.
        for config in OutputProfileManager.shared.enabledConfigurations {
            guard let shortcut = ShortcutStore.shortcut(for: .profile(config.id)) else { continue }
            items.append(HUDItem(
                id: "profile_\(config.id.uuidString)",
                icon: hudIcon(for: config),
                label: config.name,
                shortcutDisplay: shortcut.displayString
            ))
        }

        // Save targets — only those with an explicit user-set shortcut.
        for target in SaveTargetManager.shared.targets {
            let action = ShortcutAction.finishWithSaveTarget(target.id)
            guard let shortcut = ShortcutStore.shortcut(for: action) else { continue }
            items.append(HUDItem(
                id: target.id.uuidString,
                icon: target.icon,
                label: target.name,
                shortcutDisplay: shortcut.displayString
            ))
        }

        // Always-present hint: ⌘↩ finishes the current session in whatever mode
        // is active. Fixed chip, not a stored/rebindable shortcut.
        items.append(HUDItem(
            id: "recorderPanelFinish",
            icon: "return",
            label: String(localized: "Finish"),
            shortcutDisplay: "⌘↩"
        ))

        return items
    }

    /// SF Symbol name for a mode in the HUD. Mode icons can be emoji — the HUD
    /// row renders SF Symbols only, so we fall back to the outputMode icon
    /// (doc.on.clipboard etc.) for emoji-iconed modes.
    private static func hudIcon(for config: OutputProfile) -> String {
        switch config.icon.kind {
        case .symbol: return config.icon.value
        case .emoji:  return config.outputMode.iconName
        }
    }
}
