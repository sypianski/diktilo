import Testing
@testable import Diktilo

struct AppRuntimeTests {

    // If detection ever breaks, the host would boot the full app (shortcuts,
    // microphone, real SwiftData stores) instead of the bare test host.
    @Test func testHostIsDetected() {
        #expect(AppRuntime.isRunningTests)
    }

}
