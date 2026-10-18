import CoreVideo
import Testing
@testable import AutoSwitchCore

struct VirtualCameraOutputTests {
    func makeFrame(
        width: Int = VirtualCamera.width,
        height: Int = VirtualCamera.height,
        format: OSType = VirtualCamera.pixelFormat,
        backing: CVPixelBufferCreationAttributes.Backing = .ioSurface
    ) throws -> CVReadOnlyPixelBuffer {
        var attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: format),
            size: CVImageSize(width: width, height: height)
        )
        attributes.backing = backing
        return CVReadOnlyPixelBuffer(try CVMutablePixelBuffer(attributes))
    }

    @Test func sendsMatchingFramesUnchanged() throws {
        #expect(VirtualCameraOutput.canSendUnchanged(try makeFrame()))
    }

    @Test func convertsFramesOfAnotherSize() throws {
        #expect(!VirtualCameraOutput.canSendUnchanged(try makeFrame(width: 1280, height: 720)))
    }

    @Test func convertsFramesInAnotherFormat() throws {
        #expect(!VirtualCameraOutput.canSendUnchanged(try makeFrame(format: kCVPixelFormatType_32BGRA)))
    }

    @Test func convertsFramesWithoutIOSurface() throws {
        #expect(!VirtualCameraOutput.canSendUnchanged(try makeFrame(backing: .memory)))
    }
}
