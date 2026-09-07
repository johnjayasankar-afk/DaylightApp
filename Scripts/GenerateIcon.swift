import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()

    let glow = NSRect(x: size * 0.10, y: size * 0.22, width: size * 0.80, height: size * 0.70)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.28, alpha: 0.55),
        NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.11, alpha: 0)
    ])?.draw(in: NSBezierPath(ovalIn: glow), relativeCenterPosition: .zero)

    let sun = NSRect(x: size * 0.22, y: size * 0.34, width: size * 0.56, height: size * 0.56)
    NSColor(calibratedRed: 0.93, green: 0.62, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(ovalIn: sun).fill()

    NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.52, alpha: 1).setFill()
    NSBezierPath(ovalIn: sun.insetBy(dx: size * 0.08, dy: size * 0.08)).fill()

    NSColor(calibratedRed: 0.18, green: 0.14, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size * 0.42)).fill()

    NSColor(calibratedRed: 0.76, green: 0.46, blue: 0.26, alpha: 1).setStroke()
    let horizon = NSBezierPath()
    horizon.lineWidth = max(size * 0.035, 1)
    horizon.move(to: NSPoint(x: size * 0.12, y: size * 0.42))
    horizon.curve(
        to: NSPoint(x: size * 0.88, y: size * 0.42),
        controlPoint1: NSPoint(x: size * 0.35, y: size * 0.50),
        controlPoint2: NSPoint(x: size * 0.65, y: size * 0.34)
    )
    horizon.stroke()
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, size: Int, name: String) {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])
    try? data?.write(to: iconset.appendingPathComponent(name))
}

let catalog: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (size, name) in catalog {
    writePNG(drawIcon(size: CGFloat(size)), size: size, name: name)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
print("Wrote \(root.appendingPathComponent("Resources/AppIcon.icns").path)")
