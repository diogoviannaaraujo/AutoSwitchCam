import Foundation

/// Picks the camera with the most movement. Passes when nothing moves enough.
///
/// Movement is counted in patches, not pixels. A patch moves only when enough
/// of its pixels change together, so scattered changes from compression,
/// night-vision grain or a clock overlay don't count. How much a pixel has to
/// change depends on the picture's contrast, so movement in a dark camera
/// counts about as much as in a bright one.
final class MotionMode: SwitchingMode {
    struct Settings {
        /// How much movement counts, from 0 (Low: a lot of the picture has to move) to 1 (High: a little is enough).
        var sensitivity = 0.5
        /// How much a pixel's brightness must change to count, as a share of the picture's contrast.
        var relativeChange = 0.12
        /// The smallest brightness change (0–255) that counts, however flat the picture, so sensor noise in a dark picture doesn't.
        var minimumChange = 6
        /// The width and height of a patch, in analysis pixels.
        var patchSize = 10
        /// The share of a patch's pixels that must change for the patch to count as moving.
        var patchFill = 0.2
        /// How far another camera's score must beat the live camera's before Motion switches.
        var switchMargin = 0.02
        /// Weight of the newest frame in the smoothed score (an exponential moving average).
        var smoothing = 0.3
        /// How long a camera can go without frames before Motion forgets its movement,
        /// for example while no app is showing the AutoSwitchCam camera and the cameras are off.
        var maximumFrameGap = Duration.seconds(1)

        /// The smoothed share of moving patches a camera needs before Motion picks it. Anything less counts as no movement.
        /// It goes from 20% of the picture at the lowest sensitivity to 2% at the highest.
        var minimumMovement: Double {
            0.2 * pow(0.1, min(max(sensitivity, 0), 1))
        }
    }

    static let id = "motion"

    var settings: Settings
    /// Each camera's smoothed share of moving patches, from 0 to 1.
    private(set) var scores: [CameraID: Double] = [:]
    private var previousFrames: [CameraID: AnalysisFrame] = [:]

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    func analyze(_ frame: AnalysisFrame) {
        defer { previousFrames[frame.camera] = frame }
        // After a gap, the camera starts over: comparing with an old frame would look like movement.
        guard let previous = previousFrames[frame.camera], frame.time - previous.time <= settings.maximumFrameGap else {
            scores[frame.camera] = nil
            return
        }
        guard previous.luma.width == frame.luma.width, previous.luma.height == frame.luma.height else { return }
        let moving = Self.movingShare(from: previous.luma, to: frame.luma, settings: settings)
        let score = scores[frame.camera] ?? 0
        scores[frame.camera] = score + settings.smoothing * (moving - score)
    }

    func pick(from cameras: [CameraID], live: CameraID?, now: ContinuousClock.Instant) -> CameraID? {
        let candidates = cameras.compactMap { camera in score(of: camera, now: now).map { (camera: camera, score: $0) } }
        guard let best = candidates.max(by: { $0.score < $1.score }), best.score >= settings.minimumMovement else {
            return nil
        }
        // Stay on the live camera unless another camera clearly moves more.
        if let live, live != best.camera, cameras.contains(live),
           let liveScore = score(of: live, now: now), best.score < liveScore + settings.switchMargin {
            return live
        }
        return best.camera
    }

    /// A camera's score, or nil before it has one or once its frames stop coming.
    private func score(of camera: CameraID, now: ContinuousClock.Instant) -> Double? {
        guard let frame = previousFrames[camera], now - frame.time <= settings.maximumFrameGap else { return nil }
        return scores[camera]
    }

    /// The share of patches in which enough pixels changed brightness.
    static func movingShare(from previous: LumaImage, to current: LumaImage, settings: Settings) -> Double {
        let width = current.width, height = current.height
        guard width > 0, height > 0, previous.pixels.count == current.pixels.count, current.pixels.count == width * height else {
            return 0
        }
        let threshold = max(settings.minimumChange, Int((settings.relativeChange * Double(contrast(of: current))).rounded()))
        let size = settings.patchSize
        let patchesAcross = (width + size - 1) / size
        let patchesDown = (height + size - 1) / size
        var changed = [Int](repeating: 0, count: patchesAcross * patchesDown)

        // Raw buffers keep this cheap in Debug builds too; it runs 10 times a second per camera.
        previous.pixels.withUnsafeBufferPointer { old in
            current.pixels.withUnsafeBufferPointer { new in
                for y in 0..<height {
                    let row = y * width
                    let patchRow = (y / size) * patchesAcross
                    for x in 0..<width where abs(Int(new[row + x]) - Int(old[row + x])) > threshold {
                        changed[patchRow + x / size] += 1
                    }
                }
            }
        }

        var moving = 0
        for patch in changed.indices {
            // Patches on the right and bottom edges can be smaller than the rest.
            let patchWidth = min(size, width - (patch % patchesAcross) * size)
            let patchHeight = min(size, height - (patch / patchesAcross) * size)
            if Double(changed[patch]) >= settings.patchFill * Double(patchWidth * patchHeight) {
                moving += 1
            }
        }
        return Double(moving) / Double(changed.count)
    }

    /// The spread between the picture's darker and brighter pixels (the 5th and 95th percentiles), from 0 to 255.
    static func contrast(of image: LumaImage) -> Int {
        var histogram = [Int](repeating: 0, count: 256)
        image.pixels.withUnsafeBufferPointer { pixels in
            for value in pixels {
                histogram[Int(value)] += 1
            }
        }
        func percentile(_ share: Double) -> Int {
            let target = Int(Double(image.pixels.count) * share)
            var total = 0
            for (value, count) in histogram.enumerated() {
                total += count
                if total > target { return value }
            }
            return 255
        }
        return percentile(0.95) - percentile(0.05)
    }
}
