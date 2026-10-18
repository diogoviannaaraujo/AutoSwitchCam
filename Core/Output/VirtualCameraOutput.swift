import CoreMedia
import CoreVideo
import os

/// Sends the live camera's frames to the virtual camera as they arrive, at up
/// to the virtual camera's frame rate. A frame that already has the virtual
/// camera's size and pixel format goes as it is; any other frame is converted.
actor VirtualCameraOutput {
    private let frameStore: FrameStore
    private var sink: SinkStreamClient?
    private var nextSinkCheck = ContinuousClock.now
    /// The last connection failure, so each new reason is logged once instead of every second.
    private var lastSinkError: SinkError?
    /// How the last frame was sent, so each change is logged once instead of every frame.
    private var lastPath: Path?

    private enum Path: Equatable {
        case unchanged(CameraID)
        case converted(CameraID, from: CVImageSize, format: CVPixelFormatType)
    }

    /// Frames closer together than this are skipped, so a 60 fps camera comes
    /// out at 30 fps while a 30 fps camera with uneven timing loses none.
    private static let minimumFrameGap = Duration.seconds(1) / VirtualCamera.frameRate * 0.75

    init(frameStore: FrameStore) {
        self.frameStore = frameStore
    }

    /// Sends frames until the task is cancelled, then disconnects from the
    /// sink stream so the extension stops reading it. While no frames come,
    /// nothing is sent and the extension shows its placeholder.
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
        defer {
            sink = nil
            lastPath = nil
        }

        nextSinkCheck = .now
        var lastSent: ContinuousClock.Instant?
        for await live in frameStore.makeLiveFrames() {
            let now = ContinuousClock.now
            if let lastSent, now - lastSent < Self.minimumFrameGap { continue }
            updateSink(now: now)
            guard let sink else { continue }
            send(live, to: sink, pool: pool, scaler: scaler)
            lastSent = now
        }
    }

    /// Whether a frame can go to the virtual camera as it is: it has the camera's
    /// size and pixel format, and IOSurface backing so it crosses to the extension without a copy.
    static func canSendUnchanged(_ frame: CVReadOnlyPixelBuffer) -> Bool {
        frame.pixelFormatType.rawValue == VirtualCamera.pixelFormat
            && frame.size == CVImageSize(width: VirtualCamera.width, height: VirtualCamera.height)
            && frame.withUnsafeBackingIOSurfaceIfPresent { _ in true } ?? false
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

    private func send(_ live: LiveFrame, to sink: SinkStreamClient, pool: CVMutablePixelBuffer.Pool, scaler: PixelScaler) {
        do {
            let pixelBuffer: CVReadOnlyPixelBuffer
            if Self.canSendUnchanged(live.frame) {
                pixelBuffer = live.frame
                log(.unchanged(live.camera))
            } else {
                var buffer = try pool.makeMutablePixelBuffer()
                try scaler.transfer(live.frame, to: &buffer)
                pixelBuffer = CVReadOnlyPixelBuffer(buffer)
                log(.converted(live.camera, from: live.frame.size, format: live.frame.pixelFormatType))
            }
            let sampleBuffer = CMReadySampleBuffer(
                pixelBuffer: pixelBuffer,
                presentationTimeStamp: CMClock.hostTimeClock.time,
                duration: VirtualCamera.frameDuration
            )
            sampleBuffer.withUnsafeSampleBuffer { sink.enqueue($0) }
        } catch {
            logger.error("Couldn't send a frame: \(String(describing: error), privacy: .public)")
        }
    }

    private func log(_ path: Path) {
        guard path != lastPath else { return }
        lastPath = path
        switch path {
        case let .unchanged(camera):
            logger.info("Sending \(camera.rawValue, privacy: .public) unchanged")
        case let .converted(camera, size, format):
            logger.info("Converting \(camera.rawValue, privacy: .public) from \(size.width)×\(size.height) \(format.fourCharacterCode, privacy: .public)")
        }
    }
}

private extension CVPixelFormatType {
    /// The format's four-character code, such as "420v", for logs.
    var fourCharacterCode: String {
        String(decoding: withUnsafeBytes(of: rawValue.bigEndian) { Array($0) }, as: UTF8.self)
    }
}
