import Testing
@testable import AutoSwitchCore

struct MotionModeTests {
    let a = CameraID("A")
    let b = CameraID("B")
    let start = ContinuousClock.now

    /// Brightness that alternates every frame, which looks like movement.
    let moving: @Sendable (Int) -> UInt8 = { $0.isMultiple(of: 2) ? 50 : 200 }
    let still: @Sendable (Int) -> UInt8 = { _ in 100 }

    /// Feeds each camera `count` uniform frames, 100 ms apart, with the brightness its closure gives for each frame index.
    func feed(_ mode: MotionMode, frames count: Int, brightness: [CameraID: @Sendable (Int) -> UInt8]) {
        for index in 0..<count {
            for (camera, value) in brightness {
                let luma = LumaImage(width: 16, height: 9, pixels: Array(repeating: value(index), count: 16 * 9))
                mode.analyze(AnalysisFrame(camera: camera, luma: luma, time: start + .milliseconds(100 * index)))
            }
        }
    }

    /// A 20×10 image (two patches side by side) with brightness from a closure of x and y.
    func image(_ brightness: (Int, Int) -> UInt8) -> LumaImage {
        LumaImage(width: 20, height: 10, pixels: (0..<200).map { brightness($0 % 20, $0 / 20) })
    }

    @Test func passesWhenNothingMoves() {
        let mode = MotionMode()
        feed(mode, frames: 10, brightness: [a: still, b: still])
        #expect(mode.pick(from: [a, b], live: a, now: start) == nil)
    }

    @Test func picksTheCameraWithMovement() {
        let mode = MotionMode()
        feed(mode, frames: 10, brightness: [a: still, b: moving])
        #expect(mode.pick(from: [a, b], live: a, now: start) == b)
    }

    @Test func ignoresChangesBelowTheMinimumChange() {
        let mode = MotionMode()
        feed(mode, frames: 10, brightness: [a: still, b: { $0.isMultiple(of: 2) ? 100 : 105 }])
        #expect(mode.pick(from: [a, b], live: a, now: start) == nil)
    }

    @Test func keepsTheLiveCameraWithinTheSwitchMargin() {
        let mode = MotionMode()
        feed(mode, frames: 10, brightness: [a: moving, b: moving])
        #expect(mode.pick(from: [a, b], live: a, now: start) == a)
        #expect(mode.pick(from: [a, b], live: b, now: start) == b)
    }

    @Test func ignoresDisconnectedCameras() {
        let mode = MotionMode()
        feed(mode, frames: 10, brightness: [a: still, b: moving])
        #expect(mode.pick(from: [a], live: a, now: start) == nil)
    }

    @Test func forgetsCamerasWhoseFramesStop() {
        let mode = MotionMode()
        feed(mode, frames: 10, brightness: [a: still, b: moving])
        #expect(mode.pick(from: [a, b], live: a, now: start + .seconds(1)) == b)
        #expect(mode.pick(from: [a, b], live: a, now: start + .seconds(3)) == nil)
    }

    @Test func startsOverAfterAGapInFrames() {
        let mode = MotionMode()
        feed(mode, frames: 10, brightness: [a: still, b: moving])
        // The cameras were off for a minute, and B's first frame since is different from its last one.
        let restart = start + .seconds(60)
        let luma = LumaImage(width: 16, height: 9, pixels: Array(repeating: 100, count: 16 * 9))
        mode.analyze(AnalysisFrame(camera: b, luma: luma, time: restart))
        #expect(mode.pick(from: [a, b], live: a, now: restart) == nil)
    }

    @Test func countsPatchesWhereEnoughPixelsChange() {
        let previous = image { _, _ in 0 }
        // Half of the left patch changes, and none of the right one.
        let current = image { x, y in x < 10 && y < 5 ? 100 : 0 }
        #expect(MotionMode.movingShare(from: previous, to: current, settings: .init()) == 0.5)
    }

    @Test func ignoresScatteredChanges() {
        let previous = image { _, _ in 0 }
        // One pixel in ten changes in both patches, which is grain rather than movement.
        let current = image { x, y in (x + y * 20).isMultiple(of: 10) ? 100 : 0 }
        #expect(MotionMode.movingShare(from: previous, to: current, settings: .init()) == 0)
    }

    @Test func needsBiggerChangesInPicturesWithMoreContrast() {
        // A change of 20 counts in a flat picture but not in one that goes from black to white.
        let flat = image { _, _ in 100 }
        let flatChanged = image { _, _ in 120 }
        #expect(MotionMode.movingShare(from: flat, to: flatChanged, settings: .init()) == 1)

        let contrasty = image { _, y in y < 5 ? 0 : 235 }
        let contrastyChanged = image { _, y in y < 5 ? 20 : 255 }
        #expect(MotionMode.movingShare(from: contrasty, to: contrastyChanged, settings: .init()) == 0)
    }

    @Test func contrastSpansTheMiddleNinetyPercentOfPixels() {
        #expect(MotionMode.contrast(of: image { _, _ in 80 }) == 0)
        #expect(MotionMode.contrast(of: image { _, y in y < 5 ? 10 : 200 }) == 190)
    }

    @Test func passesOnMovementBelowTheMinimum() {
        // One patch in ten keeps moving: 10% of the picture.
        let frames = (0..<10).map { index in
            LumaImage(width: 100, height: 10, pixels: (0..<1000).map { $0 % 100 < 10 ? moving(index) : 100 })
        }
        func pick(sensitivity: Double) -> CameraID? {
            let mode = MotionMode(settings: .init(sensitivity: sensitivity))
            for (index, luma) in frames.enumerated() {
                mode.analyze(AnalysisFrame(camera: b, luma: luma, time: start + .milliseconds(100 * index)))
            }
            return mode.pick(from: [a, b], live: a, now: start)
        }
        #expect(pick(sensitivity: 0) == nil, "Low needs 20% of the picture to move")
        #expect(pick(sensitivity: 1) == b, "High needs 2%")
    }
}
