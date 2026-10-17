import CoreMedia
import CoreVideo
import Foundation

/// Names, IDs and the video format that the app and the camera extension agree on.
/// This file is compiled into both AutoSwitchCore and the camera extension.
public enum VirtualCamera {
    /// The camera name that Zoom, Meet, FaceTime and other apps show.
    public static let name = "AutoSwitchCam"
    public static let manufacturer = "AutoSwitchCam"
    public static let model = "AutoSwitchCam Virtual Camera"

    public static let appBundleID = "com.diogoviannaaraujo.AutoSwitchCam"
    public static let extensionBundleID = "com.diogoviannaaraujo.AutoSwitchCam.CameraExtension"

    public static let deviceID = UUID(uuidString: "6EAAAED4-E790-49C3-8A63-0DA3F37DC766")!
    public static let sourceStreamID = UUID(uuidString: "0D454D70-534A-45BA-90A3-9827E3322D14")!
    public static let sinkStreamID = UUID(uuidString: "E074D01E-6999-446E-93AE-FAF6FED71DE7")!

    /// The four-character code of a custom device property that the extension
    /// publishes: "1" while an app is reading the camera's video, "0" otherwise.
    /// The app only runs the cameras while it's "1".
    static let inUseSelector = "inus"
    /// The in-use property's name in the extension. Core Media I/O passes a custom
    /// property through to apps when its name is "4cc_" followed by the selector,
    /// scope and element as four-character codes.
    static let inUsePropertyName = "4cc_\(inUseSelector)_glob_0000"

    public static let width = 1920
    public static let height = 1080
    public static let frameRate = 30
    public static let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    /// BGRA, so the extension can draw its placeholder with CoreGraphics.
    public static let pixelFormat = kCVPixelFormatType_32BGRA

    public static var pixelBufferAttributes: CVPixelBufferCreationAttributes {
        var attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: pixelFormat),
            size: CVImageSize(width: width, height: height)
        )
        // IOSurface-backed buffers cross from the app to the extension without a copy.
        attributes.backing = .ioSurface
        return attributes
    }
}
