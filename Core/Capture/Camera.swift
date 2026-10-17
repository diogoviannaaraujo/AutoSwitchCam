/// Identifies a camera by its `AVCaptureDevice.uniqueID`, which stays the same across launches.
public struct CameraID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

/// A camera that AutoSwitchCam can switch to.
public struct Camera: Identifiable, Hashable, Sendable {
    /// How the camera is connected to the Mac.
    public enum Kind: Sendable {
        case builtIn
        case usb
        case continuity
        /// A camera made by software, such as OBS Virtual Camera.
        case virtual
        case other
    }

    public let id: CameraID
    public let name: String
    public let kind: Kind
}
