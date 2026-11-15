import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputPath = CommandLine.arguments.last ?? "AppIcon.png"
let outputURL = URL(fileURLWithPath: outputPath)

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fatalError("Could not create the app icon graphics context.")
}

context.setFillColor(CGColor(red: 0.043, green: 0.055, blue: 0.078, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let mark = CGMutablePath()
mark.move(to: CGPoint(x: 184, y: 706))
mark.addLine(to: CGPoint(x: 364, y: 326))
mark.addLine(to: CGPoint(x: 512, y: 590))
mark.addLine(to: CGPoint(x: 660, y: 326))
mark.addLine(to: CGPoint(x: 840, y: 706))

context.addPath(mark)
context.setStrokeColor(CGColor(red: 0.79, green: 0.95, blue: 0.42, alpha: 1))
context.setLineWidth(104)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

guard let image = context.makeImage() else {
    fatalError("Could not render the WatchTrack app icon.")
}
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Could not create the PNG output destination.")
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write the WatchTrack app icon.")
}

print("Generated \(size)x\(size) WatchTrack app icon at \(outputURL.path)")
