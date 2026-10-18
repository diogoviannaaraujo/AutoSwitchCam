import CoreGraphics
import CoreText
import CoreVideo

/// The frame the camera shows while the AutoSwitchCam app isn't sending video.
enum Placeholder {
    /// Draws the placeholder in BGRA, which CoreGraphics can draw into, then
    /// converts it once to the camera's pixel format.
    ///
    /// - Parameter showsHint: Whether to add a line under the name that tells people to open the app.
    static func makePixelBuffer(showsHint: Bool) throws -> CVReadOnlyPixelBuffer {
        var drawing = try CVMutablePixelBuffer(CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: VirtualCamera.width, height: VirtualCamera.height)
        ))
        drawing.accessUnsafeMutableRawPlaneBytes { planes in
            guard let plane = planes.first,
                  let context = CGContext(
                      data: plane.bytes.baseAddress,
                      width: plane.properties.size.width,
                      height: plane.properties.size.height,
                      bitsPerComponent: 8,
                      bytesPerRow: plane.properties.bytesPerRow,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                  )
            else { return }
            draw(in: context, size: CGSize(width: plane.properties.size.width, height: plane.properties.size.height), showsHint: showsHint)
        }
        var buffer = try CVMutablePixelBuffer(VirtualCamera.pixelBufferAttributes)
        try PixelScaler().transfer(CVReadOnlyPixelBuffer(drawing), to: &buffer)
        return CVReadOnlyPixelBuffer(buffer)
    }

    private static func draw(in context: CGContext, size: CGSize, showsHint: Bool) {
        context.setFillColor(CGColor(gray: 0.11, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let nameY = showsHint ? size.height / 2 + 40 : size.height / 2
        drawCentered("AutoSwitchCam", fontSize: 96, emphasized: true, gray: 1, centerY: nameY, width: size.width, in: context)
        if showsHint {
            drawCentered("Open the AutoSwitchCam app to start video", fontSize: 40, emphasized: false, gray: 0.6, centerY: size.height / 2 - 60, width: size.width, in: context)
        }
    }

    private static func drawCentered(_ text: String, fontSize: CGFloat, emphasized: Bool, gray: CGFloat, centerY: CGFloat, width: CGFloat, in context: CGContext) {
        guard let font = CTFontCreateUIFontForLanguage(emphasized ? .emphasizedSystem : .system, fontSize, nil) else { return }
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: gray, alpha: 1),
        ] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.minX, y: centerY - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, context)
    }
}
