#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Expected an iconset output directory.")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

let variants: [(pixels: Int, names: [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]

func iconPNG(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphicsContext

    let context = graphicsContext.cgContext
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)

    context.setFillColor(
        CGColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1)
    )
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
            cornerWidth: 224,
            cornerHeight: 224,
            transform: nil
        )
    )
    context.fillPath()

    context.setStrokeColor(
        CGColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
    )
    context.setLineWidth(44)
    context.setLineCap(.butt)
    context.setLineJoin(.miter)

    context.beginPath()
    context.move(to: CGPoint(x: 512, y: 904))
    context.addLine(to: CGPoint(x: 904, y: 512))
    context.addLine(to: CGPoint(x: 512, y: 120))
    context.addLine(to: CGPoint(x: 120, y: 512))
    context.closePath()
    context.strokePath()

    context.beginPath()
    context.move(to: CGPoint(x: 512, y: 904))
    context.addLine(to: CGPoint(x: 512, y: 120))
    context.move(to: CGPoint(x: 512, y: 722))
    context.addLine(to: CGPoint(x: 316, y: 316))
    context.move(to: CGPoint(x: 512, y: 722))
    context.addLine(to: CGPoint(x: 708, y: 316))
    context.strokePath()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for variant in variants {
    let data = try iconPNG(pixels: variant.pixels)
    for name in variant.names {
        try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
    }
}
