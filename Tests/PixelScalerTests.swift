import CoreVideo
import Testing
@testable import AutoSwitchCore

struct PixelScalerTests {
    func makeBuffer(width: Int, height: Int, format: OSType) throws -> CVMutablePixelBuffer {
        var attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: format),
            size: CVImageSize(width: width, height: height)
        )
        attributes.backing = .ioSurface
        return try CVMutablePixelBuffer(attributes)
    }

    /// Fills every byte of each plane with the value given for it.
    func fill(_ buffer: inout CVMutablePixelBuffer, planes values: [UInt8]) {
        buffer.accessUnsafeMutableRawPlaneBytes { planes in
            for (plane, value) in zip(planes, values) {
                plane.bytes.initializeMemory(as: UInt8.self, repeating: value)
            }
        }
    }

    /// The brightness and the two color values of a 420v pixel.
    func ycbcr(of buffer: CVReadOnlyPixelBuffer, x: Int, y: Int) -> (y: Int, cb: Int, cr: Int) {
        buffer.accessUnsafeRawPlaneBytes { planes in
            let luma = planes[0], chroma = planes[1]
            let cbIndex = (y / 2) * chroma.properties.bytesPerRow + (x / 2) * 2
            return (
                Int(luma.bytes[y * luma.properties.bytesPerRow + x]),
                Int(chroma.bytes[cbIndex]),
                Int(chroma.bytes[cbIndex + 1])
            )
        }
    }

    @Test func convertsBGRAToTheCameraFormatWithoutATint() throws {
        var source = try makeBuffer(width: VirtualCamera.width, height: VirtualCamera.height, format: kCVPixelFormatType_32BGRA)
        fill(&source, planes: [128])
        var destination = try CVMutablePixelBuffer(VirtualCamera.pixelBufferAttributes)
        try PixelScaler().transfer(CVReadOnlyPixelBuffer(source), to: &destination)

        let result = CVReadOnlyPixelBuffer(destination)
        #expect(result.pixelFormatType.rawValue == VirtualCamera.pixelFormat)
        let pixel = ycbcr(of: result, x: VirtualCamera.width / 2, y: VirtualCamera.height / 2)
        // Gray stays gray: both color values are neutral.
        #expect(abs(pixel.cb - 128) <= 2)
        #expect(abs(pixel.cr - 128) <= 2)
    }

    @Test func addsBlackBarsToA4By3Frame() throws {
        var source = try makeBuffer(width: 640, height: 480, format: VirtualCamera.pixelFormat)
        fill(&source, planes: [200, 128])
        var destination = try CVMutablePixelBuffer(VirtualCamera.pixelBufferAttributes)
        try PixelScaler().transfer(CVReadOnlyPixelBuffer(source), to: &destination)

        let result = CVReadOnlyPixelBuffer(destination)
        // The picture is 1440 wide, so 240-pixel bars are left on each side.
        let bar = ycbcr(of: result, x: 100, y: VirtualCamera.height / 2)
        #expect(abs(bar.y - 16) <= 1, "Video-range black")
        #expect(abs(bar.cb - 128) <= 1 && abs(bar.cr - 128) <= 1, "Neutral, not green")
        let picture = ycbcr(of: result, x: VirtualCamera.width / 2, y: VirtualCamera.height / 2)
        #expect(abs(picture.y - 200) <= 10)
    }
}
