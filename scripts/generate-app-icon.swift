// Regenerate the App Store icon with: swift scripts/generate-app-icon.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("App/Assets.xcassets")
let output = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.28, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.21, blue: 0.38, alpha: 1),
               ending: NSColor(calibratedRed: 0.03, green: 0.1, blue: 0.2, alpha: 1))!.draw(in: tile, angle: -90)

    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 260, y: 344, width: 504, height: 304), xRadius: 64, yRadius: 64).fill()
    NSBezierPath(roundedRect: NSRect(x: 386, y: 604, width: 252, height: 100), xRadius: 32, yRadius: 32).fill()
    NSColor(calibratedRed: 0.06, green: 0.17, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 408, y: 392, width: 208, height: 208)).fill()
    let accent = NSColor(calibratedRed: 0.22, green: 0.89, blue: 0.76, alpha: 1)
    accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: 448, y: 432, width: 128, height: 128)).fill()

    func arrow(from start: NSPoint, to end: NSPoint, direction: CGFloat) {
        accent.setStroke()
        let line = NSBezierPath()
        line.lineWidth = 38
        line.lineCapStyle = .round
        line.move(to: start)
        line.line(to: end)
        line.stroke()
        let head = NSBezierPath()
        head.lineWidth = 38
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.move(to: NSPoint(x: end.x - direction * 60, y: end.y + 58))
        head.line(to: end)
        head.line(to: NSPoint(x: end.x - direction * 60, y: end.y - 58))
        head.stroke()
    }
    arrow(from: NSPoint(x: 304, y: 784), to: NSPoint(x: 720, y: 784), direction: 1)
    arrow(from: NSPoint(x: 720, y: 244), to: NSPoint(x: 304, y: 244), direction: -1)
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(size) / 1024)
    (transform as NSAffineTransform).concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon-\(size).png"))
}
let images = [16, 32, 128, 256, 512].flatMap { size in
    [1, 2].map { scale in
        ["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": "icon-\(size * scale).png"]
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"))
