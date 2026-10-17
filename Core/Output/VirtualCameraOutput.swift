import CoreMedia
import CoreVideo
import os

/// Sends the live camera's latest frame to the virtual camera at a steady frame rate.
actor VirtualCameraOutput {
    private let frameStore: FrameStore
    private var liveCamera: CameraID?
    private var sink: SinkStreamClient?
    private var nextSinkCheck = ContinuousClock.now
    /// The last connection failure, so each new reason is logged once instead of every second.
    private var lastSinkError: SinkError?

    init(frameStore: FrameStore) {
        self.frameStore = frameStore
    }

    func setLiveCamera(_ camera: CameraID?) {
        liveCamera = camera
    }

    /// Runs the output clock until the task is cancelled, then disconnects from
    /// the sink stream so the extension stops reading it.
    func run() async {
        let pool: CVMutablePixelBuffer.Pool
        let scaler: PixelScaler
        do {
            pool = try CVMutablePixelBuffer.Pool(pixelBufferAttributes: VirtualCamera.pixelBufferAttributes)
            scaler = try PixelScaler()
        } catch {
            logger.fault("Couldn't set up the video output: \(String(describing: error), privacy: .public)")
            return
        }
        defer { sink = nil }

        let clock = ContinuousClock()
        let interval = Duration.seconds(1) / VirtualCamera.frameRate
        var deadline = clock.now
        nextSinkCheck = deadline
        while !Task.isCancelled {
            let now = clock.now
            updateSink(now: now)
            // Without a live camera, nothing is sent and the extension shows its placeholder.
            if let sink, let liveCamera, let frame = frameStore.latestFrame(for: liveCamera) {
                send(frame, to: sink, pool: pool, scaler: scaler)
            }
            deadline = max(deadline + interval, now)
            try? await clock.sleep(until: deadline, tolerance: .milliseconds(2))
        }
    }

    /// Connects to the camera extension's sink stream, and reconnects when the
    /// camera disappears, for example after the extension is updated.
    private func updateSink(now: ContinuousClock.Instant) {
        guard now >= nextSinkCheck else { return }
        nextSinkCheck = now + .seconds(1)
        if let sink, SinkStreamClient.findDevice() == sink.deviceID { return }
        if sink != nil {
            logger.info("Lost the virtual camera")
            sink = nil
        }
        do {
            sink = try SinkStreamClient.connect()
            lastSinkError = nil
            logger.info("Connected to the virtual camera")
        } catch {
            if error != lastSinkError {
                logger.error("Can't send video to the virtual camera: \(error.description, privacy: .public)")
                lastSinkError = error
            }
        }
    }

    private func send(_ frame: CVReadOnlyPixelBuffer, to sink: SinkStreamClient, pool: CVMutablePixelBuffer.Pool, scaler: PixelScaler) {
        do {
            var buffer = try pool.makeMutablePixelBuffer()
            try scaler.transfer(frame, to: &buffer)
            let sampleBuffer = CMReadySampleBuffer(
                pixelBuffer: CVReadOnlyPixelBuffer(buffer),
                presentationTimeStamp: CMClock.hostTimeClock.time,
                duration: VirtualCamera.frameDuration
            )
            sampleBuffer.withUnsafeSampleBuffer { sink.enqueue($0) }
        } catch {
            logger.error("Couldn't send a frame: \(String(describing: error), privacy: .public)")
        }
    }
}
