import AppKit
import CoreGraphics
import Foundation
@testable import BabelCore
@testable import BabelOCR
@testable import BabelTranslate
@testable import BabelLexicon
@testable import BabelSpeech
@testable import LanguageDanish
@testable import BabelstaarnetKit

/// Covers the properties the OCR passes depend on: whatever colours a crop
/// uses, preparation has to hand back dark text on a light background with the
/// glyphs still separated from the background.
@main
enum OCRImagePreparationChecks {
    static func main() {
        checkPolarityIsNormalized()
        checkEquiluminantColoursSeparate()
        checkLowContrastIsExpanded()
        checkUniformCropIsRejected()
        checkRuleRemovalKeepsFilledAreas()
        checkOtsuSplitsTwoModes()
        checkEnlargementRespectsBudget()
        print("OCR image preparation checks passed")
    }

    // MARK: - Separation

    /// Dark-on-light and light-on-dark must both come back dark-on-light.
    private static func checkPolarityIsNormalized() {
        for (background, foreground) in [
            (rgb(255, 255, 255), rgb(0, 0, 0)),
            (rgb(24, 24, 28), rgb(236, 236, 240))
        ] {
            guard let prepared = OCRImagePreparation.separated(
                from: stripes(
                    background: background,
                    foreground: foreground
                )
            ) else {
                preconditionFailure("Separation returned no result.")
            }
            precondition(
                isDarkTextOnLightBackground(prepared),
                "Prepared crop was not dark text on a light background."
            )
            precondition(
                contrastSpan(prepared) >= wellSeparatedSpan,
                "Prepared crop lost its separation: span "
                    + "\(contrastSpan(prepared))."
            )
        }
    }

    /// Red on green has almost no luminance difference. A grayscale conversion
    /// collapses it; projecting onto the colour axis must not.
    private static func checkEquiluminantColoursSeparate() {
        let background = rgb(42, 123, 98)
        let foreground = rgb(200, 30, 60)
        let image = stripes(
            background: background,
            foreground: foreground
        )

        let backgroundLuminance = luminance(background)
        let foregroundLuminance = luminance(foreground)
        precondition(
            abs(backgroundLuminance - foregroundLuminance) < 24,
            "Fixture is not equiluminant, so it proves nothing."
        )

        guard let prepared = OCRImagePreparation.separated(from: image) else {
            preconditionFailure("Equiluminant crop produced no result.")
        }
        // The point of the colour axis: a luminance conversion of this crop
        // has almost no range left, while the prepared crop has full range.
        precondition(
            luminanceSpan(of: image) < 40,
            "Luminance already separated the fixture: span "
                + "\(luminanceSpan(of: image))."
        )
        precondition(
            contrastSpan(prepared) >= wellSeparatedSpan,
            "Equiluminant colours were not separated: span "
                + "\(contrastSpan(prepared))."
        )
        precondition(isDarkTextOnLightBackground(prepared))
    }

    /// Six luminance steps must be stretched to a readable range.
    private static func checkLowContrastIsExpanded() {
        guard let prepared = OCRImagePreparation.separated(
            from: stripes(
                background: rgb(244, 244, 244),
                foreground: rgb(238, 238, 238)
            )
        ) else {
            preconditionFailure("Low-contrast crop produced no result.")
        }
        precondition(
            luminanceSpan(of: stripes(
                background: rgb(244, 244, 244),
                foreground: rgb(238, 238, 238)
            )) < 12
        )
        precondition(
            contrastSpan(prepared) >= wellSeparatedSpan,
            "Low contrast was not expanded: span \(contrastSpan(prepared))."
        )
    }

    /// A crop with nothing to read must say so rather than amplify noise.
    private static func checkUniformCropIsRejected() {
        precondition(
            OCRImagePreparation.separated(
                from: solid(rgb(128, 128, 128))
            ) == nil,
            "A uniform crop should not produce a prepared image."
        )
    }

    // MARK: - Rule removal

    /// Thin rules go; a filled block stays. Without the thickness guard the
    /// same scan erases the body of a dark banner and takes its text with it.
    private static func checkRuleRemovalKeepsFilledAreas() {
        let width = 400
        let height = 120
        var grayscale = OCRImagePreparation.Grayscale(
            pixels: [UInt8](repeating: 255, count: width * height),
            width: width,
            height: height
        )
        // A two-pixel table rule.
        for row in 20..<22 {
            for column in 0..<width {
                grayscale.pixels[row * width + column] = 0
            }
        }
        // A forty-pixel filled block.
        for row in 60..<100 {
            for column in 0..<width {
                grayscale.pixels[row * width + column] = 0
            }
        }

        OCRImagePreparation.removeRules(from: &grayscale)

        precondition(
            (0..<width).allSatisfy {
                grayscale.pixels[20 * width + $0] == 255
            },
            "The thin rule was not removed."
        )
        precondition(
            (0..<width).allSatisfy {
                grayscale.pixels[80 * width + $0] == 0
            },
            "The filled block was erased along with the rules."
        )
    }

    // MARK: - Histogram

    private static func checkOtsuSplitsTwoModes() {
        var histogram = [Int](repeating: 0, count: 256)
        for bucket in 30..<40 {
            histogram[bucket] = 500
        }
        for bucket in 200..<210 {
            histogram[bucket] = 500
        }
        let threshold = OCRImagePreparation.otsuThreshold(
            histogram: histogram
        )
        // The threshold is the last bucket of the dark class, so any value
        // from the top of the first mode up to the foot of the second one
        // separates them.
        precondition(
            threshold >= 39 && threshold < 200,
            "Otsu threshold \(threshold) fell outside the valley."
        )

        let empty = OCRImagePreparation.otsuThreshold(
            histogram: [Int](repeating: 0, count: 256)
        )
        precondition(empty == 128)
    }

    // MARK: - Enlargement

    private static func checkEnlargementRespectsBudget() {
        let image = solid(rgb(255, 255, 255), width: 200, height: 100)
        guard let doubled = OCRImagePreparation.enlarged(
            image,
            scale: 2
        ) else {
            preconditionFailure("Enlargement returned no image.")
        }
        precondition(doubled.width == 400 && doubled.height == 200)
        precondition(
            OCRImagePreparation.enlarged(image, scale: 1) == nil,
            "Enlarging by one should be refused as pointless work."
        )
        precondition(
            OCRImagePreparation.enlarged(image, scale: 400) == nil,
            "Enlargement ignored the pixel budget."
        )
    }

    // MARK: - Helpers

    /// The two class means are stretched to a quarter-gap inside each end of
    /// the range, so a cleanly separated crop lands near 42...212. Anything
    /// approaching this means both classes survived; a collapse reads near 0.
    private static let wellSeparatedSpan = 160

    private static func luminanceSpan(of image: CGImage) -> Int {
        guard let rgba = OCRImagePreparation.rgbaPixels(from: image) else {
            return 0
        }
        var low = 255
        var high = 0
        for pixel in 0..<(image.width * image.height) {
            let index = pixel * 4
            let value = (77 * Int(rgba[index])
                + 150 * Int(rgba[index + 1])
                + 29 * Int(rgba[index + 2])) >> 8
            low = min(low, value)
            high = max(high, value)
        }
        return high - low
    }

    private static func contrastSpan(
        _ grayscale: OCRImagePreparation.Grayscale
    ) -> Int {
        let low = grayscale.pixels.min().map(Int.init) ?? 0
        let high = grayscale.pixels.max().map(Int.init) ?? 0
        return high - low
    }

    /// True when the light class outnumbers the dark one, which is what
    /// "dark text on a light page" means for a crop of text.
    private static func isDarkTextOnLightBackground(
        _ grayscale: OCRImagePreparation.Grayscale
    ) -> Bool {
        let dark = grayscale.pixels.count { $0 < 128 }
        return dark * 2 < grayscale.pixels.count
    }

    private static func luminance(_ color: NSColor) -> Double {
        0.299 * Double(color.redComponent * 255)
            + 0.587 * Double(color.greenComponent * 255)
            + 0.114 * Double(color.blueComponent * 255)
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    private static func solid(
        _ color: NSColor,
        width: Int = 200,
        height: Int = 100
    ) -> CGImage {
        draw(width: width, height: height) { bounds in
            color.setFill()
            bounds.fill()
        }
    }

    /// Stand-in for text: a minority of foreground pixels on a background,
    /// which is the pixel distribution preparation is tuned for.
    private static func stripes(
        background: NSColor,
        foreground: NSColor
    ) -> CGImage {
        draw(width: 300, height: 120) { bounds in
            background.setFill()
            bounds.fill()
            foreground.setFill()
            for column in stride(from: 10, to: 290, by: 20) {
                NSRect(x: CGFloat(column), y: 40, width: 4, height: 40).fill()
            }
        }
    }

    private static func draw(
        width: Int,
        height: Int,
        body: (NSRect) -> Void
    ) -> CGImage {
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
            preconditionFailure("Could not create the check bitmap.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        body(NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else {
            preconditionFailure("Could not render the check bitmap.")
        }
        return image
    }
}
