import AppKit
import Foundation

enum AppRuntime {
    /// Environment variables xcodebuild sets on the test host process to inject
    /// and drive the test bundle (XCTest and Swift Testing alike).
    static let testHostEnvironmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier",
        "XCInjectBundleInto"
    ]

    /// True when this process is the host of a unit test run. The host shares
    /// the installed Diktilo's bundle id, preferences domain and Application
    /// Support folder, so it must not start any part of the real app.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return testHostEnvironmentKeys.contains { environment[$0] != nil }
    }()
}

@main
@MainActor
enum DiktiloMain {
    static func main() {
        if AppRuntime.isRunningTests {
            TestHostApp.main()
        } else {
            VoiceInkApp.main()
        }
    }
}

/// Bare AppKit run loop for hosting unit tests. No delegate, scenes, menu bar
/// item, shortcuts, audio, SwiftData stores or background services — only the
/// event loop the injected test bundle needs to run. Tests that need a model
/// container create their own in memory.
@MainActor
enum TestHostApp {
    static func main() {
        let app = NSApplication.shared
        // Never show up in the Dock or the menu bar, never take focus.
        app.setActivationPolicy(.prohibited)
        app.run()
    }
}
