import AppKit
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

public enum BabelstaarnetIcon {
    public static let inactiveMenuBarImage = makeMenuBarImage(active: false)
    public static let activeMenuBarImage = makeMenuBarImage(active: true)

    private static func makeMenuBarImage(active: Bool) -> NSImage {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in
            let top = NSPoint(x: 9, y: 16.25)
            let right = NSPoint(x: 16.25, y: 9)
            let bottom = NSPoint(x: 9, y: 1.75)
            let left = NSPoint(x: 1.75, y: 9)
            let junction = NSPoint(x: 9, y: 12.9)
            let lowerLeft = NSPoint(x: 5.375, y: 5.375)
            let lowerRight = NSPoint(x: 12.625, y: 5.375)

            if active {
                let lowerFacets = NSBezierPath()
                lowerFacets.move(to: junction)
                lowerFacets.line(to: lowerLeft)
                lowerFacets.line(to: bottom)
                lowerFacets.line(to: lowerRight)
                lowerFacets.close()
                NSColor.black.setFill()
                lowerFacets.fill()
            }

            let outline = NSBezierPath()
            outline.move(to: top)
            outline.line(to: right)
            outline.line(to: bottom)
            outline.line(to: left)
            outline.close()

            let structure = NSBezierPath()
            structure.move(to: top)
            structure.line(to: bottom)
            structure.move(to: junction)
            structure.line(to: lowerLeft)
            structure.move(to: junction)
            structure.line(to: lowerRight)

            NSColor.black.setStroke()
            for path in [outline, structure] {
                path.lineWidth = 1.25
                path.lineCapStyle = .butt
                path.lineJoinStyle = .miter
                path.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
