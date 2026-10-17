import Testing
@testable import AutoSwitchCore

struct ManualModeTests {
    let a = CameraID("A")
    let b = CameraID("B")

    @Test func picksThePinnedCamera() {
        let mode = ManualMode()
        mode.pinned = b
        #expect(mode.pick(from: [a, b], live: a, now: .now) == b)
    }

    @Test func passesWhenNothingIsPinned() {
        #expect(ManualMode().pick(from: [a, b], live: a, now: .now) == nil)
    }

    @Test func passesWhenThePinnedCameraIsDisconnected() {
        let mode = ManualMode()
        mode.pinned = b
        #expect(mode.pick(from: [a], live: a, now: .now) == nil)
    }

    @Test func bypassesTheAntiFlickerRules() {
        #expect(ManualMode().bypassesAntiFlicker)
    }
}
