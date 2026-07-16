import Foundation

/// One-shot migration from the legacy global "Finish → Copy/Paste/Edit Window"
/// shortcuts (`ShortcutAction.finishWithCopy/.finishWithPaste/.finishWithEditWindow`)
/// to per-mode finish shortcuts (`ShortcutAction.profile(id)`).
///
/// For each fixed destination that still has an effective binding (an explicit
/// user binding OR the Ctrl+Option fallback that has not been cleared), a shim
/// `OutputProfile` is created with the matching `outputMode`, the same
/// keystroke is reattached to `.profile(shim.id)`, and the legacy action is
/// cleared so it stops firing globally.
///
/// AI enhancement on the shims is left OFF to preserve today's semantics: the
/// legacy Ctrl+Opt+C/V/E flow did not run enhancement on top of the active
/// mode's own enhancement. A future global-AI-toggle + per-mode-AI-toggle pass
/// will revisit this.
///
/// Runs once. Guarded by a UserDefaults flag; the migration reads persistent
/// state from `OutputProfileManager.shared` and `ShortcutStore` and does not
/// depend on SwiftUI or the recording engine, so it is safe to call from app
/// init before the rest of the shortcut machinery spins up.
enum LegacyFinishShortcutMigration {
    private static let migrationKey = "legacyFinishShortcutMigrationV1_done"

    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let manager = OutputProfileManager.shared

        let mappings: [(action: ShortcutAction, outputMode: OutputMode, name: String, symbol: String)] = [
            (.finishWithCopy,       .copy,       "Copy",        "doc.on.doc"),
            (.finishWithPaste,      .paste,      "Paste",       "doc.on.clipboard"),
            (.finishWithEditWindow, .editWindow, "Edit Window", "square.and.pencil")
        ]

        for mapping in mappings {
            // `effectiveShortcut` folds explicit binding + Ctrl+Option fallback.
            // We treat both the same way: whatever the user currently reaches
            // for keeps working after the migration, just in a per-mode slot.
            guard let shortcut = FinishDestinationBindings.effectiveShortcut(for: mapping.action) else {
                continue
            }

            let shimName = uniqueName(base: mapping.name, existing: manager.configurations.map(\.name))
            let shim = OutputProfile(
                name: shimName,
                icon: .symbol(mapping.symbol),
                isAIEnhancementEnabled: false,
                outputMode: mapping.outputMode,
                isEnabled: true,
                isDefault: false
            )

            manager.addConfiguration(shim)
            ShortcutStore.setShortcut(shortcut, for: .profile(shim.id))
            // Clear (not just remove) the legacy binding so that
            // `FinishDestinationBindings.effectiveShortcut` no longer falls
            // back to Ctrl+Opt+C/V/E for this action.
            ShortcutStore.setShortcut(nil, for: mapping.action)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private static func uniqueName(base: String, existing: [String]) -> String {
        let existingSet = Set(existing)
        if !existingSet.contains(base) { return base }
        var suffix = 2
        while existingSet.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }
}
