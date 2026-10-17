import os

/// Rules the Director applies to automatic picks so the video doesn't cut back and forth.
struct AntiFlickerRules: Sendable {
    /// A camera stays live at least this long before an automatic switch.
    var minimumHold: Duration
    /// A new automatic pick has to last this long before it takes effect.
    var switchDelay: Duration
    /// When every mode passes for this long, the main camera goes live.
    var mainCameraDelay: Duration

    static let standard = AntiFlickerRules(minimumHold: .seconds(3), switchDelay: .milliseconds(500), mainCameraDelay: .seconds(5))
}

/// Decides which camera is live. It asks the modes from top to bottom, takes
/// the first pick and applies the anti-flicker rules. If every mode passes for
/// a while, it goes back to the main camera.
actor Director {
    /// Emits the live camera every time it changes.
    let liveChanges: AsyncStream<CameraID?>
    private(set) var live: CameraID?

    private let liveContinuation: AsyncStream<CameraID?>.Continuation
    private let modes: [any SwitchingMode]
    private let rules: AntiFlickerRules
    private var cameras: [CameraID] = []
    /// The main camera chosen in Settings, connected or not.
    private var preferredMainCamera: CameraID?
    private var liveSince: ContinuousClock.Instant?
    /// An automatic pick that's waiting out the switch delay.
    private var pending: (camera: CameraID, since: ContinuousClock.Instant)?
    /// When every mode started passing, or nil while one of them picks a camera.
    private var stillSince: ContinuousClock.Instant?

    init(modes: [any SwitchingMode] = [ManualMode(), MotionMode()], rules: AntiFlickerRules = .standard) {
        self.modes = modes
        self.rules = rules
        let (stream, continuation) = AsyncStream<CameraID?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        liveChanges = stream
        liveContinuation = continuation
    }

    /// Feeds every analysis frame to the modes and re-evaluates after each one.
    func run(_ frames: AsyncStream<AnalysisFrame>) async {
        for await frame in frames {
            analyze(frame)
        }
    }

    func analyze(_ frame: AnalysisFrame) {
        for mode in modes {
            mode.analyze(frame)
        }
        evaluate(now: frame.time)
    }

    func setCameras(_ cameras: [CameraID], now: ContinuousClock.Instant = .now) {
        self.cameras = cameras
        evaluate(now: now)
    }

    /// Pins a camera in the Manual mode, or unpins with nil.
    func pin(_ camera: CameraID?, now: ContinuousClock.Instant = .now) {
        for case let manual as ManualMode in modes {
            manual.pinned = camera
        }
        evaluate(now: now)
    }

    /// Sets the camera to go back to when nothing is happening. With nil, or
    /// while that camera isn't connected, the first camera is the main one.
    func setMainCamera(_ camera: CameraID?, now: ContinuousClock.Instant = .now) {
        preferredMainCamera = camera
        evaluate(now: now)
    }

    /// Sets how much movement the Motion mode needs, from 0 (Low) to 1 (High).
    func setMotionSensitivity(_ sensitivity: Double) {
        for case let motion as MotionMode in modes {
            motion.settings.sensitivity = sensitivity
        }
    }

    func evaluate(now: ContinuousClock.Instant) {
        guard let mainCamera else {
            pending = nil
            stillSince = nil
            setLive(nil, now: now)
            return
        }
        let pick = firstPick(now: now)
        if pick == nil {
            stillSince = stillSince ?? now
        } else {
            stillSince = nil
        }

        // With no live camera, or after the live camera is disconnected, switch at once.
        guard let live, cameras.contains(live) else {
            pending = nil
            if let pick {
                setLive(pick.camera, now: now, reason: type(of: pick.mode).id)
            } else {
                setLive(mainCamera, now: now, reason: "main camera")
            }
            return
        }
        guard let pick else {
            pending = nil
            // Nothing is happening anywhere, so go back to the main camera once it's been still for a while.
            if live != mainCamera, let stillSince, now - stillSince >= rules.mainCameraDelay,
               let liveSince, now - liveSince >= rules.minimumHold {
                setLive(mainCamera, now: now, reason: "main camera")
            }
            return
        }
        guard pick.camera != live else {
            pending = nil
            return
        }
        if pick.mode.bypassesAntiFlicker {
            pending = nil
            setLive(pick.camera, now: now, reason: type(of: pick.mode).id)
            return
        }

        if pending?.camera != pick.camera {
            pending = (pick.camera, now)
        }
        if let pending, now - pending.since >= rules.switchDelay,
           let liveSince, now - liveSince >= rules.minimumHold {
            self.pending = nil
            setLive(pending.camera, now: now, reason: type(of: pick.mode).id)
        }
    }

    /// The main camera chosen in Settings, or the first camera while that one isn't connected.
    private var mainCamera: CameraID? {
        if let preferredMainCamera, cameras.contains(preferredMainCamera) {
            return preferredMainCamera
        }
        return cameras.first
    }

    private func firstPick(now: ContinuousClock.Instant) -> (camera: CameraID, mode: any SwitchingMode)? {
        for mode in modes {
            if let camera = mode.pick(from: cameras, live: live, now: now) {
                return (camera, mode)
            }
        }
        return nil
    }

    private func setLive(_ camera: CameraID?, now: ContinuousClock.Instant, reason: String = "no cameras") {
        guard camera != live else { return }
        live = camera
        liveSince = now
        liveContinuation.yield(camera)
        logger.info("Live camera: \(camera?.rawValue ?? "none", privacy: .public) (\(reason, privacy: .public))")
    }
}
