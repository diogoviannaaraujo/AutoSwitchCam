import CoreMediaIO
import Dispatch

/// Tells whether an app is showing the AutoSwitchCam camera. The camera
/// extension publishes this as a custom device property and announces every
/// change. A check once a second also finds the camera when the extension
/// starts after the app, and catches a change if an announcement goes missing.
actor VirtualCameraUsage {
    /// Emits whether an app is showing the camera, every time that changes.
    let changes: AsyncStream<Bool>

    private let continuation: AsyncStream<Bool>.Continuation
    private var isInUse = false
    private var device: CMIODeviceID?
    private var listener: CMIOProperty.Listener?

    private static let selector = CMIOProperty.selector(VirtualCamera.inUseSelector)

    init() {
        (changes, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Checks once a second until the task is cancelled.
    func run() async {
        while !Task.isCancelled {
            followDevice()
            update()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Listens to the camera that's there now, which changes when the extension starts or restarts.
    private func followDevice() {
        let found = SinkStreamClient.findDevice()
        guard found != device else { return }
        device = found
        listener = found.flatMap { device in
            CMIOProperty.Listener(Self.selector, on: device, queue: .global(qos: .userInitiated)) { [weak self] in
                Task { await self?.update() }
            }
        }
    }

    private func update() {
        let isInUse = device.map(Self.isInUse) ?? false
        guard isInUse != self.isInUse else { return }
        self.isInUse = isInUse
        continuation.yield(isInUse)
    }

    /// An extension from before the property existed doesn't publish it, so its camera counts as always in use.
    private static func isInUse(_ device: CMIODeviceID) -> Bool {
        guard CMIOProperty.exists(selector, on: device) else { return true }
        return CMIOProperty.string(of: device, selector: selector) == "1"
    }
}
