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
}
