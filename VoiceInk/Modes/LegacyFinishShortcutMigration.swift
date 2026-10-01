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
/// The Ctrl+Option fallback only counts on an install that ran those old
/// versions (onboarding completed). On a fresh install it is nobody's choice:
/// only explicitly stored bindings migrate, and `DefaultModeSeeder` provides
/// the starting modes instead.
///
/// Runs once. Guarded by a UserDefaults flag; the migration reads persistent
/// state from `OutputProfileManager.shared` and `ShortcutStore` and does not
/// depend on SwiftUI or the recording engine, so it is safe to call from app
/// init before the rest of the shortcut machinery spins up.
enum LegacyFinishShortcutMigration {
    private static let migrationKey = "legacyFinishShortcutMigrationV1_done"
    private static let completedOnboardingKey = "hasCompletedOnboardingV2"

    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let manager = OutputProfileManager.shared
        let isExistingInstall = UserDefaults.standard.bool(forKey: completedOnboardingKey)

        let mappings: [(action: ShortcutAction, outputMode: OutputMode, name: String, symbol: String)] = [
            (.finishWithCopy,       .copy,       String(localized: "Copy"),        "doc.on.doc"),
            (.finishWithPaste,      .paste,      String(localized: "Paste"),       "doc.on.clipboard"),
            (.finishWithEditWindow, .editWindow, String(localized: "Edit Window"), "square.and.pencil")
        ]

        for mapping in mappings {
            // On an existing install `effectiveShortcut` folds explicit binding
            // + Ctrl+Option fallback: whatever the user reaches for keeps
            // working, just in a per-mode slot.
            let legacyShortcut = isExistingInstall
                ? FinishDestinationBindings.effectiveShortcut(for: mapping.action)
                : ShortcutStore.shortcut(for: mapping.action)
            guard let shortcut = legacyShortcut else {
                ShortcutStore.setShortcut(nil, for: mapping.action)
                continue
            }

            // A mode that already finishes this way (e.g. the seeded "Copy")
            // covers it; a shim would only duplicate it.
            let isAlreadyCovered = manager.configurations.contains {
                $0.outputMode == mapping.outputMode && ShortcutStore.shortcut(for: .profile($0.id)) == shortcut
            }
            guard !isAlreadyCovered else {
                ShortcutStore.setShortcut(nil, for: mapping.action)
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
