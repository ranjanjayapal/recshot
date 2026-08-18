import AppKit
import Foundation

let sizes: [(name: String, px: Int)] = [
    ("icon_16.png", 16),
    ("icon_32.png", 32),
    ("icon_64.png", 64),
    ("icon_128.png", 128),
    ("icon_256.png", 256),
    ("icon_512.png", 512),
    ("icon_1024.png", 1024)
]

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    context.shouldAntialias = true
    NSGraphicsContext.current = context

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let iconRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = iconRect.width * 0.223

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    let squircle = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.15, alpha: 1).setFill()
    squircle.fill()

    let highlight = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.current?.saveGraphicsState()
    highlight.addClip()
    let gradient = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.16),
        NSColor.white.withAlphaComponent(0.02),
        NSColor.black.withAlphaComponent(0.18)
    ])
    gradient?.draw(in: iconRect, angle: 90)
    NSGraphicsContext.current?.restoreGraphicsState()

    func card(offsetX: CGFloat, offsetY: CGFloat, rotation: CGFloat, fill: NSColor) {
        let w = iconRect.width * 0.38
        let h = iconRect.height * 0.26
        let rect = CGRect(
            x: iconRect.minX + iconRect.width * 0.16 + offsetX,
            y: iconRect.minY + iconRect.height * 0.18 + offsetY,
            width: w,
            height: h
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: h * 0.12, yRadius: h * 0.12)
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        path.transform(using: transform as AffineTransform)
        fill.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = max(1, s / 256)
        path.stroke()
    }

    card(offsetX: s * 0.02, offsetY: s * 0.04, rotation: -11, fill: NSColor(calibratedRed: 0.35, green: 0.42, blue: 0.55, alpha: 1))
    card(offsetX: s * 0.05, offsetY: s * 0.02, rotation: 6, fill: NSColor(calibratedRed: 0.28, green: 0.55, blue: 0.52, alpha: 1))
    card(offsetX: s * 0.08, offsetY: 0, rotation: -2, fill: NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.62, alpha: 1))

    let shutterSize = iconRect.width * 0.28
    let shutterRect = CGRect(
        x: iconRect.midX - shutterSize / 2 + iconRect.width * 0.12,
        y: iconRect.midY - shutterSize / 2 + iconRect.height * 0.12,
        width: shutterSize,
        height: shutterSize
    )
    let shutter = NSBezierPath(ovalIn: shutterRect)
    NSColor(calibratedRed: 1, green: 0.42, blue: 0.28, alpha: 1).setFill()
    shutter.fill()
    NSColor.white.withAlphaComponent(0.22).setStroke()
    shutter.lineWidth = max(1, s / 180)
    shutter.stroke()

    let inner = shutterRect.insetBy(dx: shutterSize * 0.28, dy: shutterSize * 0.28)
    let hole = NSBezierPath(ovalIn: inner)
    NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
    hole.fill()
    let glass = NSBezierPath(ovalIn: inner.insetBy(dx: inner.width * 0.18, dy: inner.height * 0.18))
    NSColor(calibratedRed: 0.45, green: 0.72, blue: 0.95, alpha: 0.55).setFill()
    glass.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./RecShot/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for entry in sizes {
    let rep = drawIcon(pixels: entry.px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode \(entry.name)\n", stderr)
        exit(1)
    }
    try data.write(to: outDir.appendingPathComponent(entry.name))
}

print("Wrote icons to \(outDir.path)")
