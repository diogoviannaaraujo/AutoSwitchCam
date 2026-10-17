import Synchronization
import Testing
@testable import AutoSwitchCore

/// A mode that picks whatever the test tells it to.
private final class ScriptedMode: SwitchingMode, Sendable {
    static let id = "scripted"
    private let next = Mutex<CameraID?>(nil)

    func willPick(_ camera: CameraID?) {
        next.withLock { $0 = camera }
    }

    func pick(from cameras: [CameraID], live: CameraID?, now: ContinuousClock.Instant) -> CameraID? {
        next.withLock { $0 }
    }
}

struct DirectorTests {
    let a = CameraID("A")
    let b = CameraID("B")
    let start = ContinuousClock.now

    @Test func firstCameraGoesLiveWhenEveryModePasses() async {
        let director = Director(modes: [ScriptedMode()])
        await director.setCameras([a, b], now: start)
        #expect(await director.live == a)
    }

    @Test func pinTakesEffectImmediately() async {
        let director = Director(modes: [ManualMode(), ScriptedMode()])
        await director.setCameras([a, b], now: start)
        await director.pin(b, now: start + .milliseconds(10))
        #expect(await director.live == b)
    }

    @Test func unpinningHandsBackToTheModesBelow() async {
        let mode = ScriptedMode()
        let director = Director(modes: [ManualMode(), mode])
        await director.setCameras([a, b], now: start)
        await director.pin(b, now: start)
        mode.willPick(a)
        await director.pin(nil, now: start + .seconds(4))
        await director.evaluate(now: start + .milliseconds(4600))
        #expect(await director.live == a)
    }

    @Test func automaticPicksWaitForTheSwitchDelayAndMinimumHold() async {
        let mode = ScriptedMode()
        let director = Director(modes: [mode])
        await director.setCameras([a, b], now: start)

        mode.willPick(b)
        await director.evaluate(now: start + .seconds(1))
        #expect(await director.live == a, "the switch delay hasn't passed")
        await director.evaluate(now: start + .seconds(2))
        #expect(await director.live == a, "A hasn't been live for the minimum hold")
        await director.evaluate(now: start + .seconds(3))
        #expect(await director.live == b)
    }

    @Test func aPickThatFlipsBackRestartsTheSwitchDelay() async {
        let mode = ScriptedMode()
        let director = Director(modes: [mode])
        await director.setCameras([a, b], now: start)

        mode.willPick(b)
        await director.evaluate(now: start + .milliseconds(5000))
        mode.willPick(a)
        await director.evaluate(now: start + .milliseconds(5300))
        mode.willPick(b)
        await director.evaluate(now: start + .milliseconds(5400))
        await director.evaluate(now: start + .milliseconds(5800))
        #expect(await director.live == a)
        await director.evaluate(now: start + .milliseconds(5900))
        #expect(await director.live == b)
    }

    @Test func losingTheLiveCameraSwitchesImmediately() async {
        let director = Director(modes: [ScriptedMode()])
        await director.setCameras([a, b], now: start)
        await director.setCameras([b], now: start + .milliseconds(100))
        #expect(await director.live == b)
    }

    @Test func theMainCameraGoesLiveFirst() async {
        let director = Director(modes: [ScriptedMode()])
        await director.setMainCamera(b, now: start)
        await director.setCameras([a, b], now: start)
        #expect(await director.live == b)
    }

    @Test func goesBackToTheMainCameraWhenEverythingIsStill() async {
        let mode = ScriptedMode()
        let director = Director(modes: [mode])
        await director.setCameras([a, b], now: start)
        mode.willPick(b)
        await director.evaluate(now: start + .seconds(3))
        await director.evaluate(now: start + .milliseconds(3500))
        #expect(await director.live == b)

        mode.willPick(nil)
        await director.evaluate(now: start + .seconds(7))
        await director.evaluate(now: start + .milliseconds(11900))
        #expect(await director.live == b, "it has been still for less than the main camera delay")
        await director.evaluate(now: start + .seconds(12))
        #expect(await director.live == a)
    }

    @Test func movementRestartsTheWaitForTheMainCamera() async {
        let mode = ScriptedMode()
        let director = Director(modes: [mode])
        await director.setCameras([a, b], now: start)
        mode.willPick(b)
        await director.evaluate(now: start + .seconds(3))
        await director.evaluate(now: start + .milliseconds(3500))

        mode.willPick(nil)
        await director.evaluate(now: start + .seconds(4))
        mode.willPick(b)
        await director.evaluate(now: start + .seconds(8))
        mode.willPick(nil)
        await director.evaluate(now: start + .seconds(9))
        await director.evaluate(now: start + .seconds(13))
        #expect(await director.live == b)
        await director.evaluate(now: start + .seconds(14))
        #expect(await director.live == a)
    }

    @Test func noCamerasMeansNothingIsLive() async {
        let director = Director(modes: [ScriptedMode()])
        await director.setCameras([a], now: start)
        await director.setCameras([], now: start + .seconds(1))
        #expect(await director.live == nil)
    }
}
