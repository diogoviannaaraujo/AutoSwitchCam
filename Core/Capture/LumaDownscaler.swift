import Accelerate
import CoreVideo

/// A small grayscale image, used for motion analysis.
struct LumaImage: Sendable, Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

/// Shrinks the brightness (Y) plane of a bi-planar YUV frame to 160×90 with vImage.
struct LumaDownscaler {
    let width = 160
    let height = 90

    func downscale(_ frame: CVReadOnlyPixelBuffer) -> LumaImage? {
        frame.accessUnsafeRawPlaneBytes { planes -> LumaImage? in
            guard let luma = planes.first, let baseAddress = luma.bytes.baseAddress else { return nil }
            // vImage only reads from the source, so the mutable pointer is never written through.
            let source = vImage.PixelBuffer<vImage.Planar8>(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: luma.properties.size.width,
                height: luma.properties.size.height,
                byteCountPerRow: luma.properties.bytesPerRow
            )
            var pixels = [UInt8](repeating: 0, count: width * height)
            pixels.withUnsafeMutableBytes { bytes in
                let destination = vImage.PixelBuffer<vImage.Planar8>(
                    data: bytes.baseAddress!,
                    width: width,
                    height: height,
                    byteCountPerRow: width
                )
                source.scale(destination: destination)
            }
            return LumaImage(width: width, height: height, pixels: pixels)
        }
    }
}
