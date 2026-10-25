import AppKit
import Foundation

// Original Aster mark, drawn as vectors at every exported size.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: alpha)
}

func drawIcon(pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                  bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let panel = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900),
                             xRadius: 206, yRadius: 206)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, alpha: 0.38)
    shadow.shadowBlurRadius = 31
    shadow.shadowOffset = NSSize(width: 0, height: -13)
    shadow.set()
    color(0x131727).setFill()
    panel.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0x31344D), color(0x181D31), color(0x101525)])!
        .draw(in: panel, angle: -60)
    let rim = NSBezierPath(roundedRect: NSRect(x: 66, y: 66, width: 892, height: 892),
                           xRadius: 202, yRadius: 202)
    color(0xB7BDEA, alpha: 0.17).setStroke()
    rim.lineWidth = 2
    rim.stroke()

    // A restrained halo separates the aperture from the dark app tile.
    NSGraphicsContext.saveGraphicsState()
    panel.addClip()
    NSGradient(starting: color(0x8070FF, alpha: 0.19), ending: color(0x8070FF, alpha: 0))!
        .draw(fromCenter: NSPoint(x: 512, y: 520), radius: 40,
              toCenter: NSPoint(x: 512, y: 520), radius: 410, options: .drawsAfterEndingLocation)
    NSGraphicsContext.restoreGraphicsState()

    let palettes: [(UInt32, UInt32)] = [
        (0xEEE9FF, 0xB49BFF), (0xD2C7FF, 0x876DF5),
        (0x98B9FF, 0x6F8BEA), (0xDDD8FF, 0xA9A4FF)
    ]

    for index in 0..<4 {
        NSGraphicsContext.saveGraphicsState()
        let rotation = AffineTransform(translationByX: 512, byY: 512)
        let rotate = AffineTransform(rotationByDegrees: CGFloat(index) * 90)
        let translateBack = AffineTransform(translationByX: -512, byY: -512)
        (rotation as NSAffineTransform).concat()
        (rotate as NSAffineTransform).concat()
        (translateBack as NSAffineTransform).concat()

        let petal = NSBezierPath()
        petal.move(to: NSPoint(x: 478, y: 546))
        petal.curve(to: NSPoint(x: 448, y: 754),
                    controlPoint1: NSPoint(x: 389, y: 612),
                    controlPoint2: NSPoint(x: 377, y: 708))
        petal.curve(to: NSPoint(x: 592, y: 709),
                    controlPoint1: NSPoint(x: 520, y: 800),
                    controlPoint2: NSPoint(x: 596, y: 782))
        petal.curve(to: NSPoint(x: 546, y: 546),
                    controlPoint1: NSPoint(x: 590, y: 650),
                    controlPoint2: NSPoint(x: 553, y: 601))
        petal.curve(to: NSPoint(x: 478, y: 546),
                    controlPoint1: NSPoint(x: 522, y: 558),
                    controlPoint2: NSPoint(x: 502, y: 558))
        petal.close()

        let glow = NSShadow()
        glow.shadowColor = color(0x05071D, alpha: 0.25)
        glow.shadowBlurRadius = 12
        glow.shadowOffset = NSSize(width: 0, height: -9)
        glow.set()
        color(palettes[index].1).setFill()
        petal.fill()
        NSShadow().set()
        NSGradient(starting: color(palettes[index].0), ending: color(palettes[index].1))!
            .draw(in: petal, angle: -74)
        color(0xFFFFFF, alpha: 0.22).setStroke()
        petal.lineWidth = 1.6
        petal.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AsterIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
    }
    return png
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try drawIcon(pixels: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
print("Generated original Aster icon in \(iconset.path)")

// Also emit the standard PNG-backed ICNS container. This makes local builds
// independent of iconutil's image conversion service in restricted environments.
func bigEndianBytes(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}
let iconRepresentations: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
]
var chunks = Data()
for (kind, name) in iconRepresentations {
    let png = try Data(contentsOf: iconset.appendingPathComponent(name))
    chunks.append(Data(kind.utf8))
    chunks.append(bigEndianBytes(UInt32(png.count + 8)))
    chunks.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndianBytes(UInt32(chunks.count + 8)))
icns.append(chunks)
try icns.write(to: resources.appendingPathComponent("AppIcon.icns"))
