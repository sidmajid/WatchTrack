import AppKit
import Foundation

let size = 1024
let outputPath = CommandLine.arguments.last ?? "AppIcon.png"
let outputURL = URL(fileURLWithPath: outputPath)

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 24
) else {
    fatalError("Could not create the app icon bitmap.")
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create the app icon graphics context.")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

NSColor(calibratedRed: 0.043, green: 0.055, blue: 0.078, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

let mark = NSBezierPath()
mark.lineWidth = 104
mark.lineCapStyle = .round
mark.lineJoinStyle = .round
mark.move(to: NSPoint(x: 184, y: 706))
mark.line(to: NSPoint(x: 364, y: 326))
mark.line(to: NSPoint(x: 512, y: 590))
mark.line(to: NSPoint(x: 660, y: 326))
mark.line(to: NSPoint(x: 840, y: 706))
NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.42, alpha: 1).setStroke()
mark.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the app icon as PNG.")
}
try png.write(to: outputURL, options: .atomic)
print("Generated \(size)x\(size) WatchTrack app icon at \(outputURL.path)")
