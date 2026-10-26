import Foundation
import Testing
@testable import Diktilo

/// Which Recording-screen details start unfolded (TASK-63.8).
struct RecordingScreenTests {
    /// Isolated defaults domain — never touches the real Diktilo domain.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "RecordingScreenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func freshInstallHasDefaultSounds() {
        withDefaults { defaults in
            #expect(!CustomSoundManager.hasNonDefaultSounds(in: defaults))
        }
    }

    @Test func persistedDefaultSelectionIsStillDefault() {
        withDefaults { defaults in
            defaults.set("builtIn", forKey: CustomSoundManager.SoundType.start.selectionKey)
            defaults.set("builtIn", forKey: CustomSoundManager.SoundType.stop.selectionKey)
            defaults.set(CustomSoundManager.SoundType.start.defaultBuiltInSound.rawValue,
                         forKey: CustomSoundManager.SoundType.start.builtInSoundKey)
            #expect(!CustomSoundManager.hasNonDefaultSounds(in: defaults))
        }
    }

    @Test func otherBuiltInSoundIsNonDefault() {
        withDefaults { defaults in
            defaults.set("builtIn", forKey: CustomSoundManager.SoundType.start.selectionKey)
            defaults.set(CustomSoundManager.BuiltInSound.sound1.rawValue,
                         forKey: CustomSoundManager.SoundType.start.builtInSoundKey)
            #expect(CustomSoundManager.hasNonDefaultSounds(in: defaults))
        }
    }

    @Test func mutedStopSoundIsNonDefault() {
        withDefaults { defaults in
            defaults.set("none", forKey: CustomSoundManager.SoundType.stop.selectionKey)
            #expect(CustomSoundManager.hasNonDefaultSounds(in: defaults))
        }
    }

    @Test func customFileIsNonDefault() {
        withDefaults { defaults in
            defaults.set("custom", forKey: CustomSoundManager.SoundType.start.selectionKey)
            defaults.set("CustomStartSound.wav", forKey: CustomSoundManager.SoundType.start.filenameKey)
            #expect(CustomSoundManager.hasNonDefaultSounds(in: defaults))
        }
    }

    @Test func customSelectionWithoutFileFallsBackToDefault() {
        withDefaults { defaults in
            defaults.set("custom", forKey: CustomSoundManager.SoundType.start.selectionKey)
            #expect(!CustomSoundManager.hasNonDefaultSounds(in: defaults))
        }
    }

    @Test func legacyDisabledFeedbackIsNonDefault() {
        withDefaults { defaults in
            defaults.set(false, forKey: "isSoundFeedbackEnabled")
            #expect(CustomSoundManager.hasNonDefaultSounds(in: defaults))
        }
    }
}
