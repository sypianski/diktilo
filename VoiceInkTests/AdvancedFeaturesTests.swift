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

    // MARK: Save targets detector

    private func storeTargets(_ targets: [SaveTargetConfig], in defaults: UserDefaults) {
        let data = try! JSONEncoder().encode(targets)
        defaults.set(data, forKey: SaveTargetManager.defaultsKey)
    }

    @Test func saveTargetsDetectorIsFalseWithoutTargets() {
        withDefaults { defaults in
            #expect(!AdvancedFeatures.saveTargetsInUse(in: defaults))
            storeTargets([], in: defaults)
            #expect(!AdvancedFeatures.saveTargetsInUse(in: defaults))
        }
    }

    @Test func saveTargetsDetectorIsTrueForStoredTarget() {
        withDefaults { defaults in
            let target = SaveTargetConfig(name: "Notes", strategy: .shellCommand(command: "cat >> ~/n.txt"))
            storeTargets([target], in: defaults)
            #expect(AdvancedFeatures.saveTargetsInUse(in: defaults))
        }
    }

    @Test func saveTargetsDetectorIgnoresTargetsOfRemovedStrategy() {
        withDefaults { defaults in
            let legacy = #"[{"id":"\#(UUID().uuidString)","name":"Old","icon":"x","strategy":{"type":"sako"}}]"#
            defaults.set(Data(legacy.utf8), forKey: SaveTargetManager.defaultsKey)
            #expect(!AdvancedFeatures.saveTargetsInUse(in: defaults))
        }
    }

    @Test func saveTargetsDetectorIsTrueForModeDeliveringToTarget() {
        withDefaults { defaults in
            let mode = OutputProfile(name: "Save", isAIEnhancementEnabled: false, outputMode: .saveTarget)
            store([cleanPaste(), mode], in: defaults)
            #expect(AdvancedFeatures.saveTargetsInUse(in: defaults))
        }
    }

    @Test func saveTargetsMigrationUsesRealDetector() {
        withDefaults { defaults in
            storeTargets([SaveTargetConfig(name: "Notes", strategy: .file(.init()))], in: defaults)
            AdvancedFeatures.runMigrationIfNeeded(defaults: defaults)
            #expect(AdvancedFeature.saveTargets.isEnabled(in: defaults))
            #expect(defaults.data(forKey: SaveTargetManager.defaultsKey) != nil)
        }
    }

    @Test func saveTargetsMigrationKeepsOffOnFreshInstall() {
        withDefaults { defaults in
            AdvancedFeatures.runMigrationIfNeeded(defaults: defaults)
            #expect(!AdvancedFeature.saveTargets.isEnabled(in: defaults))
        }
    }

    // MARK: Advanced outputs detector

    @Test func advancedOutputsDetectorIsFalseWithoutModes() {
        withDefaults { defaults in
            #expect(!AdvancedFeatures.advancedOutputsInUse(in: defaults))
            store([], in: defaults)
            #expect(!AdvancedFeatures.advancedOutputsInUse(in: defaults))
        }
    }

    @Test func advancedOutputsDetectorIsFalseForPasteAndCopyModes() {
        withDefaults { defaults in
            let copy = OutputProfile(name: "Copy", isAIEnhancementEnabled: false, outputMode: .copy)
            store([cleanPaste(), copy], in: defaults)
            #expect(!AdvancedFeatures.advancedOutputsInUse(in: defaults))
        }
    }

    @Test func advancedOutputsDetectorIsTrueForCustomCommandMode() {
        withDefaults { defaults in
            let mode = OutputProfile(name: "Cmd", isAIEnhancementEnabled: false, outputMode: .customCommand)
            store([cleanPaste(), mode], in: defaults)
            #expect(AdvancedFeatures.advancedOutputsInUse(in: defaults))
        }
    }

    @Test func advancedOutputsDetectorIsTrueForSaveTargetMode() {
        withDefaults { defaults in
            let mode = OutputProfile(name: "Save", isAIEnhancementEnabled: false, outputMode: .saveTarget)
            store([cleanPaste(), mode], in: defaults)
            #expect(AdvancedFeatures.advancedOutputsInUse(in: defaults))
        }
    }

    @Test func advancedOutputsMigrationUsesRealDetector() {
        withDefaults { defaults in
            let mode = OutputProfile(name: "Cmd", isAIEnhancementEnabled: false, outputMode: .customCommand)
            store([cleanPaste(), mode], in: defaults)
            AdvancedFeatures.runMigrationIfNeeded(defaults: defaults)
            #expect(AdvancedFeature.advancedOutputs.isEnabled(in: defaults))
        }
    }

    @Test func advancedOutputsMigrationKeepsOffOnFreshInstall() {
        withDefaults { defaults in
            store([cleanPaste()], in: defaults)
            AdvancedFeatures.runMigrationIfNeeded(defaults: defaults)
            #expect(!AdvancedFeature.advancedOutputs.isEnabled(in: defaults))
        }
    }

    @Test func anyModeUsesAIIsFalseWithoutModes() {
        withDefaults { defaults in
            #expect(!AdvancedFeatures.anyModeUsesAI(in: defaults))
            store([], in: defaults)
            #expect(!AdvancedFeatures.anyModeUsesAI(in: defaults))
        }
    }

    @Test func anyModeUsesAIIsFalseWhenNoModeHasAI() {
        withDefaults { defaults in
            let copy = OutputProfile(name: "Copy", isAIEnhancementEnabled: false, outputMode: .copy)
            store([cleanPaste(), copy], in: defaults)
            #expect(!AdvancedFeatures.anyModeUsesAI(in: defaults))
        }
    }

    @Test func anyModeUsesAIIsTrueWhenAModeHasAI() {
        withDefaults { defaults in
            let ai = OutputProfile(name: "AI", isAIEnhancementEnabled: true)
            store([cleanPaste(), ai], in: defaults)
            #expect(AdvancedFeatures.anyModeUsesAI(in: defaults))
        }
    }
}
