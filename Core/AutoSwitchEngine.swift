import AVFoundation
import Observation
import os

let logger = Logger(subsystem: "com.diogoviannaaraujo.AutoSwitchCore", category: "AutoSwitchCore")

/// Runs AutoSwitchCam's pipeline: camera discovery, capture, the Director and
/// the output to the virtual camera.
@MainActor
@Observable
public final class AutoSwitchEngine {
    public enum CameraAccess: Sendable {
        case unknown, granted, denied
    }

    /// Every camera that's connected right now, on or off. AutoSwitchCam's own camera is never listed.
    public private(set) var cameras: [Camera] = []
    /// The connected cameras that are on. Only these are opened and switched between.
    public var enabledCameras: [Camera] {
        cameras.filter { enabledCameraIDs.contains($0.id) }
    }
    /// Whether an app is showing the AutoSwitchCam camera. The cameras only run while one is.
    public private(set) var isInUse = false
    /// The camera the virtual camera is showing.
    public private(set) var liveCamera: CameraID?
    /// The camera pinned from the menu, or nil for Auto.
    public private(set) var pinnedCamera: CameraID?
    public private(set) var cameraAccess = CameraAccess.unknown
    /// The camera that goes live when nothing is moving: the one chosen in
    /// Settings, or the first camera that's on while that one isn't available.
    public var mainCamera: CameraID? {
        let cameras = enabledCameras.map(\.id)
        if let preferredMainCamera, cameras.contains(preferredMainCamera) {
            return preferredMainCamera
        }
        return cameras.first
    }
    /// How much movement the Motion mode needs, from 0 (Low) to 1 (High).
    public private(set) var motionSensitivity: Double

    /// The cameras turned on in Settings, connected or not. Cameras start off.
    private var enabledCameraIDs: Set<CameraID>
    /// The main camera chosen in Settings, connected or not.
    private var preferredMainCamera: CameraID?
    @ObservationIgnored private let defaults: UserDefaults
    private let frameStore: FrameStore
    private let director = Director()
    private let output: VirtualCameraOutput
    private let discovery = CameraDiscovery()
    private let usage = VirtualCameraUsage()
    private let analysisFrames: AsyncStream<AnalysisFrame>
    private let analysisContinuation: AsyncStream<AnalysisFrame>.Continuation
    @ObservationIgnored private var captures: [CameraID: CameraCapture] = [:]
    @ObservationIgnored private var outputTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    private static let enabledCamerasKey = "enabledCameras"
    private static let mainCameraKey = "mainCamera"
    private static let motionSensitivityKey = "motionSensitivity"

    /// - Parameter defaults: Where the camera settings get saved between launches.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabledCameraIDs = Set((defaults.stringArray(forKey: Self.enabledCamerasKey) ?? []).map(CameraID.init))
        preferredMainCamera = defaults.string(forKey: Self.mainCameraKey).map(CameraID.init)
        motionSensitivity = defaults.object(forKey: Self.motionSensitivityKey) as? Double ?? MotionMode.Settings().sensitivity
        let frameStore = FrameStore()
        self.frameStore = frameStore
        output = VirtualCameraOutput(frameStore: frameStore)
        let (stream, continuation) = AsyncStream<AnalysisFrame>.makeStream(bufferingPolicy: .bufferingNewest(64))
        analysisFrames = stream
        analysisContinuation = continuation
    }

    /// Asks for camera access, then captures, switches and sends video whenever
    /// an app is showing the AutoSwitchCam camera.
    public func start() async {
        guard !isStarted else { return }
        isStarted = true

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAccess = granted ? .granted : .denied
        guard granted else {
            logger.error("Camera access was denied")
            return
        }

        await director.setMainCamera(preferredMainCamera)
        await director.setMotionSensitivity(motionSensitivity)
        Task { await director.run(analysisFrames) }
        Task {
            for await camera in director.liveChanges {
                liveCamera = camera
                await output.setLiveCamera(camera)
            }
        }
        Task { await usage.run() }
        Task {
            for await isInUse in usage.changes {
                await setInUse(isInUse)
            }
        }
        discovery.start { [weak self] cameras in
            self?.update(cameras)
        }
    }

    /// Keeps a camera live, or returns to automatic switching with nil.
    public func pin(_ camera: CameraID?) {
        pinnedCamera = camera
        Task { await director.pin(camera) }
    }

    public func isEnabled(_ camera: CameraID) -> Bool {
        enabledCameraIDs.contains(camera)
    }

    /// Turns a camera on or off and saves the choice. Turning off the pinned camera returns to Auto.
    public func setEnabled(_ isEnabled: Bool, for camera: CameraID) {
        if isEnabled {
            enabledCameraIDs.insert(camera)
        } else {
            enabledCameraIDs.remove(camera)
            if pinnedCamera == camera {
                pin(nil)
            }
        }
        defaults.set(enabledCameraIDs.map(\.rawValue).sorted(), forKey: Self.enabledCamerasKey)
        updateCaptures()
    }

    /// Chooses the camera that goes live when nothing is moving, and saves the choice.
    public func setMainCamera(_ camera: CameraID) {
        preferredMainCamera = camera
        defaults.set(camera.rawValue, forKey: Self.mainCameraKey)
        Task { await director.setMainCamera(camera) }
    }

    /// Sets how much movement the Motion mode needs, from 0 (Low) to 1 (High), and saves it.
    public func setMotionSensitivity(_ sensitivity: Double) {
        motionSensitivity = sensitivity
        defaults.set(sensitivity, forKey: Self.motionSensitivityKey)
        Task { await director.setMotionSensitivity(sensitivity) }
    }

    private func update(_ cameras: [Camera]) {
        self.cameras = cameras
        updateCaptures()
    }

    /// Starts the cameras and the output when an app starts showing the
    /// AutoSwitchCam camera, and stops them when the last app stops.
    private func setInUse(_ isInUse: Bool) async {
        logger.info("\(isInUse ? "An app started" : "Every app stopped", privacy: .public) showing the AutoSwitchCam camera")
        self.isInUse = isInUse
        updateCaptures()
        if isInUse {
            outputTask = Task { await output.run() }
        } else {
            outputTask?.cancel()
            // Lets the output disconnect before another run can start.
            await outputTask?.value
            outputTask = nil
        }
    }

    /// Opens the connected cameras that are on while an app is showing the
    /// AutoSwitchCam camera, closes the rest, and tells the Director which cameras it can pick.
    private func updateCaptures() {
        let cameras = isInUse ? enabledCameras : []
        let wanted = Set(cameras.map(\.id))
        for (id, capture) in captures where !wanted.contains(id) {
            captures[id] = nil
            Task {
                await capture.stop()
                frameStore.remove(id)
            }
        }
        for camera in cameras where captures[camera.id] == nil {
            let capture = CameraCapture(camera: camera.id, frameStore: frameStore, analysisFrames: analysisContinuation)
            captures[camera.id] = capture
            Task {
                do {
                    try await capture.start()
                } catch {
                    logger.error("Couldn't start \(camera.name, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
        Task { await director.setCameras(cameras.map(\.id)) }
    }
}
