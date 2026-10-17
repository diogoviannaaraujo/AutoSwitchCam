import AVFoundation
import IOKit.audio

/// Finds the cameras, virtual ones included, and reports whenever one is
/// connected or disconnected. AutoSwitchCam's own camera is always left out,
/// so its video can't loop back into it.
@MainActor
final class CameraDiscovery {
    private var observers: [any NSObjectProtocol] = []

    /// Calls `onChange` with the current cameras, then again after every connection or disconnection.
    func start(onChange: @escaping @MainActor @Sendable ([Camera]) -> Void) {
        onChange(Self.connectedCameras())
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    onChange(Self.connectedCameras())
                }
            }
            observers.append(observer)
        }
    }

    /// Physical cameras first, then virtual ones, each in the order macOS lists them.
    static func connectedCameras() -> [Camera] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices
            .filter { $0.uniqueID != VirtualCamera.deviceID.uuidString }
            .map { Camera(id: CameraID($0.uniqueID), name: $0.localizedName, kind: Camera.Kind($0)) }
            .sorted { $0.kind != .virtual && $1.kind == .virtual }
    }
}

private extension Camera.Kind {
    init(_ device: AVCaptureDevice) {
        if device.isContinuityCamera {
            self = .continuity
            return
        }
        switch Int(device.transportType) {
        case kIOAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kIOAudioDeviceTransportTypeUSB: self = .usb
        case kIOAudioDeviceTransportTypeVirtual: self = .virtual
        default: self = .other
        }
    }
}
