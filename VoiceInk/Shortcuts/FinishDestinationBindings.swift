import Foundation
import Carbon.HIToolbox

// MARK: - Shared finish-destination binding helpers
//
// Single source of truth for:
//   1. The Option+C/V/E fallback shortcuts for the three fixed destinations.
//   2. The `DestinationHUDItem` list consumed by `RecorderDestinationHUDView`.
//
// Both `RecorderPanelShortcutManager` (registration) and the HUD (display)
// read from here so the two can never drift.

enum FinishDestinationBindings {

    // MARK: - Fallbacks (same values that used to be private in the manager)

    // Ctrl+Option so the letters don't collide with dead-key composition on the
    // Polish Pro layout (⌥C/⌥E/⌥N type ć/ę/ń there).
    static let fallbacks: [(ShortcutAction, Shortcut)] = [
        (.finishWithCopy,       .key(keyCode: UInt16(kVK_ANSI_C), modifierFlags: [.control, .option])),
        (.finishWithPaste,      .key(keyCode: UInt16(kVK_ANSI_V), modifierFlags: [.control, .option])),
        (.finishWithEditWindow, .key(keyCode: UInt16(kVK_ANSI_E), modifierFlags: [.control, .option]))
    ]

    // MARK: - Effective shortcut for a fixed destination action

    /// Returns the shortcut that will actually fire for `action`:
    /// • explicit user binding if set
    /// • fallback if not cleared
    /// • nil if cleared (user deliberately unbound it)
    static func effectiveShortcut(for action: ShortcutAction) -> Shortcut? {
        if let stored = ShortcutStore.shortcut(for: action) {
            return stored
        }
        if ShortcutStore.isShortcutCleared(for: action) {
            return nil
        }
        return fallbacks.first(where: { $0.0 == action })?.1
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

    /// Returns items for fixed destinations (Copy / Paste / Edit) that have a
    /// visible shortcut, followed by save targets that have an explicit binding.
    @MainActor
    static func hudItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Fixed three
        let fixedDefs: [(ShortcutAction, OutputMode, String)] = [
            (.finishWithCopy,       .copy,       String(localized: "Copy")),
            (.finishWithPaste,      .paste,      String(localized: "Paste")),
            (.finishWithEditWindow, .editWindow, String(localized: "Edit"))
        ]

        for (action, mode, label) in fixedDefs {
            guard let shortcut = effectiveShortcut(for: action) else { continue }
            items.append(HUDItem(
                id: action.storageName,
                icon: mode.iconName,
                label: label,
                shortcutDisplay: shortcut.displayString
            ))
        }

        // Save targets — only those with an explicit user-set shortcut
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
}
