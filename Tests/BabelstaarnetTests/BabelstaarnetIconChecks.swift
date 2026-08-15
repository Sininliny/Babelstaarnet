import AppKit
@testable import BabelstaarnetKit

@main
enum BabelstaarnetIconChecks {
    static func main() {
        let inactive = BabelstaarnetIcon.inactiveMenuBarImage
        let active = BabelstaarnetIcon.activeMenuBarImage

        precondition(inactive.size == NSSize(width: 18, height: 18))
        precondition(active.size == inactive.size)
        precondition(inactive.isTemplate)
        precondition(active.isTemplate)

        let inactiveCoverage = alphaCoverage(of: inactive)
        let activeCoverage = alphaCoverage(of: active)
        precondition(
            activeCoverage > inactiveCoverage + 100,
            "The active icon must visibly fill the lower facets."
        )

        print("Babelstaarnet icon checks passed")
    }

    private static func alphaCoverage(of image: NSImage) -> Int {
        let pixels = 72
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
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            preconditionFailure("Could not create an icon bitmap.")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var coverage = 0
        for y in 0..<pixels {
            for x in 0..<pixels where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 {
                coverage += 1
            }
        }
        return coverage
    }
}
