import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let pixelSize = Int(CommandLine.arguments[1]),
      pixelSize > 0 else {
    fputs("Usage: render-icon <pixel-size> <source.png> <output.png>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not load the source icon.\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create the icon bitmap.\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: pixelSize, height: pixelSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

let canvas = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
graphics.cgContext.clear(canvas)
graphics.cgContext.setAllowsAntialiasing(true)
graphics.cgContext.setShouldAntialias(true)
graphics.imageInterpolation = .high

let tileInset = CGFloat(pixelSize) * 0.0625
let tileRect = canvas.insetBy(dx: tileInset, dy: tileInset)
let cornerRadius = tileRect.width * (260.0 / 1254.0)
let tileClip = NSBezierPath(
    roundedRect: tileRect,
    xRadius: cornerRadius,
    yRadius: cornerRadius
)
tileClip.addClip()
sourceImage.draw(
    in: tileRect,
    from: CGRect(origin: .zero, size: sourceImage.size),
    operation: .copy,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)

graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the icon PNG.\n", stderr)
    exit(1)
}

try data.write(to: outputURL, options: .atomic)
