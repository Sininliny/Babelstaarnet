import CoreGraphics
import Foundation
import Vision

/// Checks the geometry that lets one line be re-read on its own.
///
/// Recognition on a cropped window reports boxes normalized to that window, so
/// the window has to know exactly which screen rectangle it covers. If that
/// mapping drifts, a re-read line still reads correctly but its word boxes land
/// somewhere else on screen, and the bubble opens over the wrong word — a
/// failure that looks like a hit-testing bug rather than a cropping one.
@main
enum OCRFocusWindowChecks {
    static func main() {
        checkWindowMapsBackToTheSameScreenRectangle()
        checkWindowStaysInsideTheCapture()
        checkWindowCoversTheLineItWasAskedFor()
        checkGlyphMeasurements()
        checkMinimumTextHeightIsAPixelFloor()
        print("OCR focus window checks passed")
    }

    private static let screenFrame = CGRect(
        x: 0,
        y: 0,
        width: 1_600,
        height: 1_000
    )
    private static let captureFrame = CGRect(
        x: 240,
        y: 300,
        width: 700,
        height: 220
    )

    /// A word's screen position must come out the same whether it is derived
    /// from the capture or from a window cut out of that capture.
    private static func checkWindowMapsBackToTheSameScreenRectangle() {
        let capture = makeCapture()
        let line = CGRect(x: 300, y: 380, width: 420, height: 18)
        guard let window = OCRService.window(
            around: line,
            in: capture
        ) else {
            preconditionFailure("No window was produced for a line inside the capture.")
        }

        // A word somewhere inside the window, stated in image pixels.
        let wordPixels = CGRect(x: 320, y: 220, width: 96, height: 24)
        let expected = screenRect(ofPixels: wordPixels, in: capture)

        // The same word as recognition would report it: normalized to the
        // window, then mapped with the window's own screen frame.
        let normalized = CGRect(
            x: (wordPixels.minX - window.pixelRect.minX)
                / window.pixelRect.width,
            y: (window.pixelRect.maxY - wordPixels.maxY)
                / window.pixelRect.height,
            width: wordPixels.width / window.pixelRect.width,
            height: wordPixels.height / window.pixelRect.height
        )
        let mapped = OCRService.globalRect(
            normalized,
            displayFrame: window.globalFrame
        )

        precondition(
            approximatelyEqual(mapped, expected),
            "A window re-read placed a word at \(mapped) instead of \(expected)."
        )
    }

    /// A line near an edge must not produce a crop reaching outside the image.
    private static func checkWindowStaysInsideTheCapture() {
        let capture = makeCapture()
        let corner = CGRect(
            x: captureFrame.minX + 2,
            y: captureFrame.maxY - 20,
            width: 120,
            height: 16
        )
        guard let window = OCRService.window(
            around: corner,
            in: capture
        ) else {
            preconditionFailure("No window was produced for a line at the capture edge.")
        }
        precondition(
            window.pixelRect.minX >= 0
                && window.pixelRect.minY >= 0
                && window.pixelRect.maxX <= CGFloat(capture.image.width)
                && window.pixelRect.maxY <= CGFloat(capture.image.height),
            "An edge window fell outside the capture: \(window.pixelRect)."
        )
        precondition(
            captureFrame.contains(window.globalFrame.insetBy(dx: 0.01, dy: 0.01)),
            "An edge window covered screen area the capture does not: "
                + "\(window.globalFrame)."
        )

        // A line entirely outside the capture has nothing to re-read.
        precondition(
            OCRService.window(
                around: CGRect(x: 0, y: 0, width: 40, height: 12),
                in: capture
            ) == nil
        )
    }

    /// Snapping to whole pixels must never shrink the window below the line it
    /// was built for; a clipped diacritic is the exact loss the pass exists to
    /// repair.
    private static func checkWindowCoversTheLineItWasAskedFor() {
        let capture = makeCapture()
        for offset in stride(from: 0.0, through: 0.9, by: 0.1) {
            let line = CGRect(
                x: 300.5 + offset,
                y: 380.25 + offset,
                width: 220.75,
                height: 13.5
            )
            guard let window = OCRService.window(
                around: line,
                in: capture
            ) else {
                preconditionFailure("No window at offset \(offset).")
            }
            precondition(
                window.globalFrame.contains(line),
                "A window at offset \(offset) clipped its own line: "
                    + "\(window.globalFrame) does not contain \(line)."
            )
        }
    }

    private static func checkGlyphMeasurements() {
        let table = region(
            "Månedlig betaling",
            words: [
                ("Månedlig", CGRect(x: 300, y: 380, width: 34, height: 9)),
                ("betaling", CGRect(x: 338, y: 380, width: 34, height: 9))
            ]
        )
        let heading = region(
            "Månedlig betaling",
            words: [
                ("Månedlig", CGRect(x: 300, y: 460, width: 68, height: 20)),
                ("betaling", CGRect(x: 374, y: 460, width: 68, height: 20))
            ]
        )
        guard let tableAdvance = OCRService.glyphAdvance(in: table),
              let headingAdvance = OCRService.glyphAdvance(in: heading) else {
            preconditionFailure("Glyph advance was not measurable.")
        }
        precondition(
            tableAdvance < 5.5 && headingAdvance > 5.5,
            "Fine print and body text were not separated: "
                + "\(tableAdvance) against \(headingAdvance)."
        )
        precondition(
            OCRService.glyphAdvance(
                in: region("", words: [])
            ) == nil
        )

        // A restored diacritic is a letter, which is what makes the enlarged
        // reading measurably better than the one it replaces.
        precondition(
            OCRService.letterCount(
                in: region("Månedlig", words: [])
            ) > OCRService.letterCount(
                in: region("Mnedlig", words: [])
            )
        )

        let focus = CGPoint(x: 350, y: 384)
        precondition(
            OCRService.focusedRegionIndex(
                in: [heading, table],
                at: focus
            ) == 1,
            "The pointer's own line was not the one selected."
        )
        precondition(
            OCRService.focusedRegionIndex(
                in: [table],
                at: CGPoint(x: 900, y: 900)
            ) == nil
        )
    }

    /// The same text must be searched for the same way whatever size crop it
    /// arrives in, which a fixed fraction of the image cannot do.
    private static func checkMinimumTextHeightIsAPixelFloor() {
        let short = OCRService.minimumTextHeight(
            recognitionLevel: .accurate,
            imageHeight: 500
        )
        let tall = OCRService.minimumTextHeight(
            recognitionLevel: .accurate,
            imageHeight: 1_640
        )
        precondition(
            abs(short * 500 - tall * 1_640) < 0.001,
            "A short and a tall capture asked for different real text sizes: "
                + "\(short * 500) px against \(tall * 1_640) px."
        )
        precondition(
            OCRService.minimumTextHeight(
                recognitionLevel: .accurate,
                imageHeight: 40
            ) <= 0.08,
            "A small crop asked for text taller than a usable share of itself."
        )
        precondition(
            OCRService.minimumTextHeight(
                recognitionLevel: .accurate,
                imageHeight: 0
            ) > 0
        )
    }

    // MARK: - Fixtures

    private static func makeCapture() -> CapturedDisplay {
        let width = Int(captureFrame.width * 2)
        let height = Int(captureFrame.height * 2)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            preconditionFailure("The fixture capture could not be created.")
        }
        return CapturedDisplay(
            displayID: 1,
            image: image,
            frame: captureFrame,
            screenFrame: screenFrame
        )
    }

    private static func region(
        _ text: String,
        words: [(String, CGRect)]
    ) -> TextRegion {
        TextRegion(
            sourceText: text,
            frame: words.first?.1 ?? .zero,
            screenFrame: screenFrame,
            displayID: 1,
            words: words.map {
                WordRegion(
                    sourceText: $0.0,
                    frame: $0.1,
                    screenFrame: screenFrame,
                    displayID: 1
                )
            }
        )
    }

    /// Where a rectangle of image pixels sits on screen, derived from the
    /// capture alone. Image rows run down from the top of the capture while
    /// screen coordinates run up from its bottom.
    private static func screenRect(
        ofPixels rect: CGRect,
        in capture: CapturedDisplay
    ) -> CGRect {
        let pointsPerPixelX = capture.frame.width
            / CGFloat(capture.image.width)
        let pointsPerPixelY = capture.frame.height
            / CGFloat(capture.image.height)
        return CGRect(
            x: capture.frame.minX + rect.minX * pointsPerPixelX,
            y: capture.frame.maxY - rect.maxY * pointsPerPixelY,
            width: rect.width * pointsPerPixelX,
            height: rect.height * pointsPerPixelY
        )
    }

    private static func approximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.01
            && abs(lhs.minY - rhs.minY) < 0.01
            && abs(lhs.width - rhs.width) < 0.01
            && abs(lhs.height - rhs.height) < 0.01
    }
}
