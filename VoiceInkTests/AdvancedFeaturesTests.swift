import Foundation
import Testing
@testable import Diktilo

struct AdvancedFeaturesTests {
    /// Isolated defaults domain — never touches the real Diktilo domain.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "AdvancedFeaturesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    private func detectors(_ result: Bool, for features: Set<AdvancedFeature>)
        -> [AdvancedFeature: AdvancedFeatures.Detector] {
        var map: [AdvancedFeature: AdvancedFeatures.Detector] = [:]
        for feature in features {
            map[feature] = { _ in result }
        }
        return map
    }

    @Test func allFeaturesAreOffByDefault() {
        withDefaults { defaults in
            for feature in AdvancedFeature.allCases {
                #expect(!feature.isEnabled(in: defaults))
            }
        }
    }

    @Test func migrationEnablesFeatureWithNonDefaultConfiguration() {
        withDefaults { defaults in
            AdvancedFeatures.runMigrationIfNeeded(
                defaults: defaults,
                detectors: detectors(true, for: [.modes])
            )
            #expect(AdvancedFeature.modes.isEnabled(in: defaults))
            #expect(!AdvancedFeature.saveTargets.isEnabled(in: defaults))
        }
    }

    @Test func migrationLeavesFeatureOffWhenDetectorSaysDefault() {
        withDefaults { defaults in
            AdvancedFeatures.runMigrationIfNeeded(
                defaults: defaults,
                detectors: detectors(false, for: Set(AdvancedFeature.allCases))
            )
            for feature in AdvancedFeature.allCases {
                #expect(!feature.isEnabled(in: defaults))
            }
        }
    }

    @Test func defaultDetectorsEnableNothing() {
        withDefaults { defaults in
            AdvancedFeatures.runMigrationIfNeeded(defaults: defaults)
            for feature in AdvancedFeature.allCases {
                #expect(!feature.isEnabled(in: defaults))
            }
        }
    }

    @Test func migrationRunsOnlyOnce() {
        withDefaults { defaults in
            AdvancedFeatures.runMigrationIfNeeded(
                defaults: defaults,
                detectors: detectors(false, for: Set(AdvancedFeature.allCases))
            )
            AdvancedFeatures.runMigrationIfNeeded(
                defaults: defaults,
                detectors: detectors(true, for: Set(AdvancedFeature.allCases))
            )
            for feature in AdvancedFeature.allCases {
                #expect(!feature.isEnabled(in: defaults))
            }
        }
    }

    @Test func migrationKeepsExplicitUserChoice() {
        withDefaults { defaults in
            AdvancedFeature.aiEnhancement.setEnabled(false, in: defaults)
            AdvancedFeatures.runMigrationIfNeeded(
                defaults: defaults,
                detectors: detectors(true, for: [.aiEnhancement, .modes])
            )
            #expect(!AdvancedFeature.aiEnhancement.isEnabled(in: defaults))
            #expect(AdvancedFeature.modes.isEnabled(in: defaults))
        }
    }
    // MARK: Modes detector

    private func store(_ modes: [OutputProfile], in defaults: UserDefaults) {
        let data = try! JSONEncoder().encode(modes)
        defaults.set(data, forKey: OutputProfileManager.configKey)
    }

    private func cleanPaste() -> OutputProfile {
        OutputProfile(name: "Paste", isAIEnhancementEnabled: false, isDefault: true)
    }

    @Test func modesDetectorIsFalseWithoutStoredModes() {
        withDefaults { defaults in
            #expect(!AdvancedFeatures.modesInUse(in: defaults))
            store([], in: defaults)
            #expect(!AdvancedFeatures.modesInUse(in: defaults))
        }
    }

    @Test func modesDetectorIsFalseForSingleUntouchedPasteMode() {
        withDefaults { defaults in
            store([cleanPaste()], in: defaults)
            #expect(!AdvancedFeatures.modesInUse(in: defaults))
        }
    }

    @Test func modesDetectorIsTrueForSeveralModes() {
        withDefaults { defaults in
            let copy = OutputProfile(name: "Copy", isAIEnhancementEnabled: false, outputMode: .copy)
            store([cleanPaste(), copy], in: defaults)
            #expect(AdvancedFeatures.modesInUse(in: defaults))
        }
    }

    @Test func modesDetectorIsTrueForChangedSingleMode() {
        withDefaults { defaults in
            let changed: [OutputProfile] = [
                OutputProfile(name: "Paste", isAIEnhancementEnabled: true),
                OutputProfile(name: "Paste", isAIEnhancementEnabled: false, outputMode: .copy),
                OutputProfile(name: "Paste", triggerWords: ["note"], isAIEnhancementEnabled: false),
                OutputProfile(
                    name: "Paste",
                    appConfigs: [AppConfig(bundleIdentifier: "com.example.app", appName: "Example")],
                    isAIEnhancementEnabled: false
                )
            ]
            for mode in changed {
                store([mode], in: defaults)
                #expect(AdvancedFeatures.modesInUse(in: defaults))
            }
        }
    }

    @Test func modesDetectorIsTrueForSingleModeWithOwnShortcut() {
        withDefaults { defaults in
            let mode = cleanPaste()
            store([mode], in: defaults)
            defaults.set(Data([1]), forKey: ShortcutAction.profile(mode.id).userDefaultsKey)
            #expect(AdvancedFeatures.modesInUse(in: defaults))
        }
    }

    @Test func modesMigrationUsesRealDetector() {
        withDefaults { defaults in
            store([cleanPaste(), OutputProfile(name: "Copy", isAIEnhancementEnabled: false, outputMode: .copy)], in: defaults)
            AdvancedFeatures.runMigrationIfNeeded(defaults: defaults)
            #expect(AdvancedFeature.modes.isEnabled(in: defaults))
        }
    }
}
