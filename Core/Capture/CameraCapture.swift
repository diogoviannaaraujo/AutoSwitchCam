import AVFoundation
import CoreVideo

/// Runs one camera. Every frame goes into the FrameStore for the output, and
/// ten times a second a small grayscale copy goes to the Director for analysis.
///
/// The actor runs on its own serial queue, which is also the capture session's
/// delegate queue, so frames arrive already isolated to the actor.
actor CameraCapture {
    nonisolated let camera: CameraID
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private nonisolated let queue = DispatchSerialQueue(label: "com.diogoviannaaraujo.AutoSwitchCore.capture", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let delegate = SampleBufferDelegate()
    private let frameStore: FrameStore
    private let analysisFrames: AsyncStream<AnalysisFrame>.Continuation
    private let downscaler = LumaDownscaler()
    private var lastAnalysis: ContinuousClock.Instant?

    private static let analysisInterval = Duration.milliseconds(100)

    init(camera: CameraID, frameStore: FrameStore, analysisFrames: AsyncStream<AnalysisFrame>.Continuation) {
        self.camera = camera
        self.frameStore = frameStore
        self.analysisFrames = analysisFrames
    }

    /// Opens the camera and starts streaming. This blocks the capture queue, not the caller.
    func start() throws {
        guard let device = AVCaptureDevice(uniqueID: camera.rawValue) else {
            throw CaptureError.cameraNotFound
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true
        delegate.capture = self
        output.setSampleBufferDelegate(delegate, queue: queue)

        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.cannotConfigure
        }
        session.addInput(input)
        session.addOutput(output)
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
        delegate.capture = nil
    }

    fileprivate func handle(_ frame: CVReadOnlyPixelBuffer) {
        frameStore.store(frame, for: camera)

        let now = ContinuousClock.now
        if let lastAnalysis, now - lastAnalysis < Self.analysisInterval { return }
        lastAnalysis = now
        if let luma = downscaler.downscale(frame) {
            analysisFrames.yield(AnalysisFrame(camera: camera, luma: luma, time: now))
        }
    }
}

enum CaptureError: Error {
    case cameraNotFound
    case cannotConfigure
}

/// Receives frames on the capture queue and hands them to the actor that owns that queue.
private final class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var capture: CameraCapture?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let capture, let imageBuffer = sampleBuffer.imageBuffer else { return }
        // Capture buffers aren't written to after delivery, so they can be shared read-only.
        nonisolated(unsafe) let pixelBuffer = imageBuffer
        let frame = CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer)
        capture.assumeIsolated { $0.handle(frame) }
    }
}
