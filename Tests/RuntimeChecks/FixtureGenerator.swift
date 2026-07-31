import AppKit
import Foundation

enum FixtureError: Error {
    case missingOutputPath
    case bitmapCreationFailed
    case pngEncodingFailed
}

@main
struct FixtureGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw FixtureError.missingOutputPath
        }

        let width = 1_400
        let height = 660
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw FixtureError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 50, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 38, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let lightTextAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 35, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let buttonTextAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 29, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let coloredTextAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 38, weight: .semibold),
            .foregroundColor: NSColor(
                calibratedRed: 0.12,
                green: 0.31,
                blue: 0.82,
                alpha: 1
            )
        ]
        let tinyTextAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.black
        ]

        NSColor(
            calibratedRed: 0.80,
            green: 0,
            blue: 0.22,
            alpha: 1
        ).setFill()
        NSRect(x: 40, y: 492, width: 1_280, height: 148).fill()
        "Hvid tekst på rød baggrund virker også".draw(
            at: NSPoint(x: 64, y: 582),
            withAttributes: lightTextAttributes
        )
        let button = NSRect(x: 64, y: 510, width: 820, height: 58)
        NSColor.white.setStroke()
        let buttonOutline = NSBezierPath(rect: button)
        buttonOutline.lineWidth = 2
        buttonOutline.stroke()
        "DANSKKURSER HOS A2B".draw(
            at: NSPoint(x: 86, y: 522),
            withAttributes: buttonTextAttributes
        )
        "Farvet dansk tekst".draw(
            at: NSPoint(x: 64, y: 426),
            withAttributes: coloredTextAttributes
        )

        let table = NSRect(x: 40, y: 350, width: 1_280, height: 62)
        NSColor.black.setStroke()
        let tableOutline = NSBezierPath(rect: table)
        tableOutline.lineWidth = 2
        tableOutline.stroke()
        for x in [460.0, 900.0] {
            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: x, y: table.minY))
            divider.line(to: NSPoint(x: x, y: table.maxY))
            divider.lineWidth = 2
            divider.stroke()
        }
        let rowDivider = NSBezierPath()
        rowDivider.move(to: NSPoint(x: table.minX, y: 381))
        rowDivider.line(to: NSPoint(x: table.maxX, y: 381))
        rowDivider.lineWidth = 2
        rowDivider.stroke()
        "Månedlig leje inkl. evt. møblering".draw(
            at: NSPoint(x: 50, y: 389),
            withAttributes: tinyTextAttributes
        )
        "betaling for varme og varmt vand".draw(
            at: NSPoint(x: 470, y: 389),
            withAttributes: tinyTextAttributes
        )
        "bidrag til driftsudgifter".draw(
            at: NSPoint(x: 910, y: 389),
            withAttributes: tinyTextAttributes
        )
        "Beboerindskud".draw(
            at: NSPoint(x: 50, y: 357),
            withAttributes: tinyTextAttributes
        )
        "Ydelse for indflytningsmåned".draw(
            at: NSPoint(x: 470, y: 357),
            withAttributes: tinyTextAttributes
        )
        "betaling for elektricitet".draw(
            at: NSPoint(x: 910, y: 357),
            withAttributes: tinyTextAttributes
        )

        "Godmorgen, hvordan har du det?".draw(
            at: NSPoint(x: 64, y: 290),
            withAttributes: titleAttributes
        )
        "Jeg lærer dansk hver dag.".draw(
            at: NSPoint(x: 64, y: 190),
            withAttributes: bodyAttributes
        )
        "Flyt markøren over et ord for at lære mere.".draw(
            at: NSPoint(x: 64, y: 120),
            withAttributes: bodyAttributes
        )
        "Finder  Recents  Applications".draw(
            at: NSPoint(x: 64, y: 30),
            withAttributes: bodyAttributes
        )

        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw FixtureError.pngEncodingFailed
        }
        try png.write(
            to: URL(fileURLWithPath: CommandLine.arguments[1]),
            options: .atomic
        )
    }
}
