import Carbon.HIToolbox
import Foundation

/// The modes a fresh install starts with: "Paste" — the default mode the main
/// recording shortcut runs — and "Copy", which ⌃⌥C finishes into instead.
/// Names are stored in the UI language at creation time.
enum DefaultModeSeeder {
    static let copyShortcut = Shortcut.key(
        keyCode: UInt16(kVK_ANSI_C),
        modifierFlags: [.control, .option]
    )

    /// Seeds only when there are no modes at all, so an existing setup is
    /// never touched. With the Modes feature off only "Paste" is created: no
    /// "Copy" mode and no ⌃⌥C, so no shortcut runs without a place in the UI
    /// to see or change it (PC-005).
    static func seedIfEmpty() {
        let manager = OutputProfileManager.shared
        guard manager.configurations.isEmpty,
              let paste = StarterModeFactory.makeDefaultMode() else {
            return
        }

        guard AdvancedFeature.modes.isEnabled() else {
            manager.replaceConfigurations([paste])
            manager.setActiveConfiguration(paste)
            return
        }

        let copy = OutputProfile(
            name: String(localized: "Copy"),
            icon: .symbol("doc.on.doc"),
            isAIEnhancementEnabled: false,
            outputMode: .copy,
            isEnabled: true,
            isDefault: false
        )

        manager.replaceConfigurations([paste, copy])
        ShortcutStore.setShortcut(copyShortcut, for: .profile(copy.id))
        manager.setActiveConfiguration(paste)
    }
}
