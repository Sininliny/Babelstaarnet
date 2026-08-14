import AppKit
import CoreGraphics
import Foundation
@testable import BabelstaarnetKit

/// A rendered reading situation: one cursor-sized crop, the phrases a learner
/// must be able to recover from it, and the exact word the pointer rests on.
///
/// Scenarios are declared instead of captured so that colour, contrast, and
/// layout can be varied one axis at a time and the resulting OCR accuracy
/// stays comparable between runs.
struct OCRScenario: Sendable {
    /// The colour or format property the scenario isolates.
    enum Axis: String, Sendable {
        case polarity
        case contrast
        case chroma
        case background
        case density
        case typography
    }

    let name: String
    let axis: Axis
    let image: CGImage
    let captureFrame: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
    /// Words every pass is expected to recover somewhere in the crop.
    let expectedWords: [String]
    /// The word under the pointer, and where the pointer sits in screen points.
    let focusWord: String
    let focusPoint: CGPoint

    var capture: CapturedDisplay {
        CapturedDisplay(
            displayID: displayID,
            image: image,
            frame: captureFrame,
            screenFrame: screenFrame
        )
    }
}

enum OCRScenarioError: Error {
    case bitmapCreationFailed
    case imageCreationFailed
    case missingFocusWord(String)
}

/// Draws one scenario at Retina scale and converts drawn text positions into
/// the screen coordinates the OCR services report, so the benchmark can assert
/// on the word actually under the pointer rather than on loose text matching.
final class OCRScenarioCanvas {
    /// Screen points per rendered pixel; every capture the app performs on a
    /// Retina display arrives at this scale.
    static let scale: CGFloat = 2

    private(set) var focusPoint: CGPoint?
    private let captureFrame: CGRect
    private var focusWord: String?

    init(captureFrame: CGRect) {
        self.captureFrame = captureFrame
    }

    func fill(_ color: NSColor, _ rect: NSRect) {
        color.setFill()
        rect.fill()
    }

    func horizontalGradient(
        from start: NSColor,
        to end: NSColor,
        in rect: NSRect
    ) {
        NSGradient(starting: start, ending: end)?.draw(in: rect, angle: 0)
    }

    func stroke(_ color: NSColor, _ rect: NSRect, width: CGFloat = 2) {
        color.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = width
        path.stroke()
    }

    func line(
        _ color: NSColor,
        from: NSPoint,
        to: NSPoint,
        width: CGFloat = 2
    ) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = width
        path.stroke()
    }

    /// Draws one line of text. When `focus` names a word in the line, the
    /// pointer position is recorded at that word's centre.
    func text(
        _ string: String,
        at origin: NSPoint,
        font: NSFont,
        color: NSColor,
        tracking: CGFloat = 0,
        focus: String? = nil
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        if tracking != 0 {
            attributes[.kern] = tracking
        }
        string.draw(at: origin, withAttributes: attributes)

        guard let focus,
              let range = string.range(of: focus) else {
            return
        }
        let prefix = String(string[string.startIndex..<range.lowerBound])
        let prefixWidth = (prefix as NSString).size(
            withAttributes: attributes
        ).width
        let wordSize = (focus as NSString).size(withAttributes: attributes)
        let centre = NSPoint(
            x: origin.x + prefixWidth + wordSize.width / 2,
            y: origin.y + wordSize.height / 2
        )
        focusWord = focus
        focusPoint = CGPoint(
            x: captureFrame.minX + centre.x / Self.scale,
            y: captureFrame.minY + centre.y / Self.scale
        )
    }

    func recordedFocusWord() -> String? {
        focusWord
    }
}

enum OCRScenarioFactory {
    static let displayID: CGDirectDisplayID = 42
    static let screenFrame = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
    /// A crop the size the adaptive planner produces for ordinary body text.
    static let captureFrame = CGRect(x: 240, y: 300, width: 700, height: 220)

    static func allScenarios() throws -> [OCRScenario] {
        [
            try lightBody(),
            try darkBody(),
            try lowContrastLight(),
            try lowContrastDark(),
            try whiteOnRedBanner(),
            try whiteOnBlueButton(),
            try equiluminantChroma(),
            try linkOnWhite(),
            try yellowOnPurple(),
            try gradientBanner(),
            try denseTableLight(),
            try denseTableDark(),
            try trackedCapitals(),
            try translucentPanel(),
            try italicSerif(),
            try faintLabelOnLight(),
            try faintLabelOnDark(),
            try tinyChroma(),
            try splitBackground(),
            try bannerWithButton()
        ]
    }

    /// A crop that straddles a light reading pane and a dark sidebar. One
    /// threshold for the whole crop has to pick a side.
    private static func splitBackground() throws -> OCRScenario {
        try scenario(
            name: "split-background",
            axis: .background,
            expected: ["Kapitel", "fire", "Emner", "Noter"],
            focus: "Kapitel"
        ) { canvas, bounds in
            canvas.fill(.white, bounds)
            canvas.fill(
                rgb(0x1B1D22),
                NSRect(x: 0, y: 0, width: 420, height: bounds.height)
            )
            canvas.text(
                "Emner",
                at: NSPoint(x: 40, y: 260),
                font: .systemFont(ofSize: 30, weight: .semibold),
                color: rgb(0xE4E4E9)
            )
            canvas.text(
                "Noter",
                at: NSPoint(x: 40, y: 190),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: rgb(0xE4E4E9)
            )
            canvas.text(
                "Kapitel fire handler om",
                at: NSPoint(x: 470, y: 260),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0x141414),
                focus: "Kapitel"
            )
            canvas.text(
                "de danske øer i vest.",
                at: NSPoint(x: 470, y: 180),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0x141414)
            )
        }
    }

    /// White text inside an outlined button on a saturated banner, sitting
    /// directly above banner text on the same colour.
    private static func bannerWithButton() throws -> OCRScenario {
        try scenario(
            name: "banner-with-button",
            axis: .background,
            expected: ["DANSKKURSER", "HOS", "Hvid", "tekst", "rød"],
            focus: "DANSKKURSER"
        ) { canvas, bounds in
            canvas.fill(.white, bounds)
            canvas.fill(
                rgb(0xCC0038),
                NSRect(x: 20, y: 60, width: bounds.width - 40, height: 300)
            )
            canvas.text(
                "Hvid tekst på rød baggrund",
                at: NSPoint(x: 52, y: 280),
                font: .systemFont(ofSize: 34, weight: .regular),
                color: .white
            )
            let button = NSRect(x: 52, y: 110, width: 700, height: 120)
            canvas.stroke(.white, button, width: 3)
            canvas.text(
                "DANSKKURSER HOS A2B",
                at: NSPoint(x: 76, y: 150),
                font: .systemFont(ofSize: 30, weight: .bold),
                color: .white,
                focus: "DANSKKURSER"
            )
        }
    }

    // MARK: - Measured failure cases

    // The three scenarios below were each measured at 0.00 recall on the raw
    // capture. They are the reason preparation exists, and they are the first
    // things to break if its thresholds drift.

    /// Six luminance steps between label and panel.
    private static func faintLabelOnLight() throws -> OCRScenario {
        try scenario(
            name: "faint-label-light",
            axis: .contrast,
            expected: ["Vedhæftede", "filer", "slettes"],
            focus: "Vedhæftede"
        ) { canvas, bounds in
            canvas.fill(gray(244), bounds)
            canvas.text(
                "Vedhæftede filer slettes",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: gray(238),
                focus: "Vedhæftede"
            )
            canvas.text(
                "efter tredive dage.",
                at: NSPoint(x: 48, y: 160),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: gray(238)
            )
        }
    }

    /// Eight luminance steps on a dark panel.
    private static func faintLabelOnDark() throws -> OCRScenario {
        try scenario(
            name: "faint-label-dark",
            axis: .contrast,
            expected: ["Kladden", "gemmes", "automatisk"],
            focus: "gemmes"
        ) { canvas, bounds in
            canvas.fill(gray(26), bounds)
            canvas.text(
                "Kladden gemmes automatisk",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: gray(34),
                focus: "gemmes"
            )
            canvas.text(
                "hvert femte minut.",
                at: NSPoint(x: 48, y: 160),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: gray(34)
            )
        }
    }

    /// Small saturated glyphs on a saturated background of the same luminance.
    private static func tinyChroma() throws -> OCRScenario {
        try scenario(
            name: "tiny-chroma",
            axis: .chroma,
            expected: ["Betingelser", "gælder", "for", "tilbuddet"],
            focus: "Betingelser"
        ) { canvas, bounds in
            canvas.fill(rgb(0x2A7B62), bounds)
            canvas.text(
                "Betingelser gælder for tilbuddet",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 14, weight: .regular),
                color: rgb(0xC81E3C),
                focus: "Betingelser"
            )
            canvas.text(
                "og kan ændres uden varsel.",
                at: NSPoint(x: 48, y: 200),
                font: .systemFont(ofSize: 14, weight: .regular),
                color: rgb(0xC81E3C)
            )
        }
    }

    private static func gray(_ value: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(value) / 255,
            green: CGFloat(value) / 255,
            blue: CGFloat(value) / 255,
            alpha: 1
        )
    }

    // MARK: - Polarity

    private static func lightBody() throws -> OCRScenario {
        try scenario(
            name: "light-body",
            axis: .polarity,
            expected: ["Jeg", "lærer", "dansk", "hver", "dag"],
            focus: "markøren"
        ) { canvas, bounds in
            canvas.fill(.white, bounds)
            canvas.text(
                "Jeg lærer dansk hver dag.",
                at: NSPoint(x: 48, y: 280),
                font: .systemFont(ofSize: 34, weight: .regular),
                color: .black
            )
            canvas.text(
                "Flyt markøren over et ord.",
                at: NSPoint(x: 48, y: 190),
                font: .systemFont(ofSize: 34, weight: .regular),
                color: .black,
                focus: "markøren"
            )
        }
    }

    private static func darkBody() throws -> OCRScenario {
        try scenario(
            name: "dark-body",
            axis: .polarity,
            expected: ["Vinduet", "lukkes", "automatisk", "om", "aftenen"],
            focus: "automatisk"
        ) { canvas, bounds in
            canvas.fill(rgb(0x1C1C1E), bounds)
            canvas.text(
                "Vinduet lukkes automatisk om aftenen.",
                at: NSPoint(x: 48, y: 260),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0xEBEBF5),
                focus: "automatisk"
            )
            canvas.text(
                "Du kan slå det fra i indstillinger.",
                at: NSPoint(x: 48, y: 170),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0xEBEBF5)
            )
        }
    }

    // MARK: - Contrast

    private static func lowContrastLight() throws -> OCRScenario {
        try scenario(
            name: "low-contrast-light",
            axis: .contrast,
            expected: ["Sidst", "opdateret", "klokken"],
            focus: "opdateret"
        ) { canvas, bounds in
            canvas.fill(rgb(0xF2F2F7), bounds)
            canvas.text(
                "Sidst opdateret i går klokken ni.",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: rgb(0x9A9AA0),
                focus: "opdateret"
            )
            canvas.text(
                "Kladden gemmes hvert minut.",
                at: NSPoint(x: 48, y: 160),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: rgb(0x9A9AA0)
            )
        }
    }

    private static func lowContrastDark() throws -> OCRScenario {
        try scenario(
            name: "low-contrast-dark",
            axis: .contrast,
            expected: ["Ingen", "nye", "beskeder", "indbakken"],
            focus: "beskeder"
        ) { canvas, bounds in
            canvas.fill(rgb(0x1C1C1E), bounds)
            canvas.text(
                "Ingen nye beskeder i indbakken.",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: rgb(0x5E5E63),
                focus: "beskeder"
            )
            canvas.text(
                "Træk ned for at hente igen.",
                at: NSPoint(x: 48, y: 160),
                font: .systemFont(ofSize: 30, weight: .regular),
                color: rgb(0x5E5E63)
            )
        }
    }

    // MARK: - Chroma

    private static func whiteOnRedBanner() throws -> OCRScenario {
        try scenario(
            name: "white-on-red",
            axis: .chroma,
            expected: ["Hvid", "tekst", "på", "rød", "baggrund"],
            focus: "baggrund"
        ) { canvas, bounds in
            canvas.fill(.white, bounds)
            canvas.fill(
                rgb(0xCC0038),
                NSRect(x: 0, y: 90, width: bounds.width, height: 250)
            )
            canvas.text(
                "Hvid tekst på rød baggrund",
                at: NSPoint(x: 48, y: 230),
                font: .systemFont(ofSize: 34, weight: .regular),
                color: .white,
                focus: "baggrund"
            )
            canvas.text(
                "virker også her.",
                at: NSPoint(x: 48, y: 140),
                font: .systemFont(ofSize: 34, weight: .regular),
                color: .white
            )
        }
    }

    private static func whiteOnBlueButton() throws -> OCRScenario {
        try scenario(
            name: "white-on-blue-button",
            axis: .chroma,
            expected: ["TILMELD", "DIG", "KURSET"],
            focus: "KURSET"
        ) { canvas, bounds in
            canvas.fill(rgb(0xF7F7FA), bounds)
            let button = NSRect(x: 48, y: 170, width: 560, height: 90)
            canvas.fill(rgb(0x0A84FF), button)
            canvas.text(
                "TILMELD DIG KURSET",
                at: NSPoint(x: 78, y: 196),
                font: .systemFont(ofSize: 32, weight: .bold),
                color: .white,
                focus: "KURSET"
            )
            canvas.text(
                "Tilmeldingen er bindende.",
                at: NSPoint(x: 48, y: 90),
                font: .systemFont(ofSize: 26, weight: .regular),
                color: rgb(0x3C3C43)
            )
        }
    }

    /// Red on green: two saturated colours with almost the same luminance, so
    /// every grayscale threshold collapses the text into the background.
    private static func equiluminantChroma() throws -> OCRScenario {
        try scenario(
            name: "equiluminant-chroma",
            axis: .chroma,
            expected: ["Rød", "skrift", "på", "grøn", "flade"],
            focus: "skrift"
        ) { canvas, bounds in
            canvas.fill(rgb(0x2A7B62), bounds)
            canvas.text(
                "Rød skrift på grøn flade",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 36, weight: .semibold),
                color: rgb(0xC81E3C),
                focus: "skrift"
            )
            canvas.text(
                "kan stadig læses her.",
                at: NSPoint(x: 48, y: 150),
                font: .systemFont(ofSize: 36, weight: .semibold),
                color: rgb(0xC81E3C)
            )
        }
    }

    private static func linkOnWhite() throws -> OCRScenario {
        try scenario(
            name: "blue-link-on-white",
            axis: .chroma,
            expected: ["Læs", "mere", "om", "vilkårene"],
            focus: "vilkårene"
        ) { canvas, bounds in
            canvas.fill(.white, bounds)
            canvas.text(
                "Læs mere om vilkårene her.",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0x0645AD),
                focus: "vilkårene"
            )
            canvas.text(
                "Prisen er 195 kroner i alt.",
                at: NSPoint(x: 48, y: 160),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0x0645AD)
            )
        }
    }

    private static func yellowOnPurple() throws -> OCRScenario {
        try scenario(
            name: "yellow-on-purple",
            axis: .chroma,
            expected: ["Gule", "bogstaver", "på", "lilla"],
            focus: "bogstaver"
        ) { canvas, bounds in
            canvas.fill(rgb(0x3B1E5A), bounds)
            canvas.text(
                "Gule bogstaver på mørk lilla",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 34, weight: .regular),
                color: rgb(0xFFD60A),
                focus: "bogstaver"
            )
            canvas.text(
                "bruges tit i reklamer.",
                at: NSPoint(x: 48, y: 155),
                font: .systemFont(ofSize: 34, weight: .regular),
                color: rgb(0xFFD60A)
            )
        }
    }

    // MARK: - Background

    /// A gradient defeats any single global threshold: the same white glyph is
    /// high contrast on the left of the crop and nearly invisible on the right.
    private static func gradientBanner() throws -> OCRScenario {
        try scenario(
            name: "gradient-banner",
            axis: .background,
            expected: ["Tekst", "over", "en", "glidende", "baggrund"],
            focus: "glidende"
        ) { canvas, bounds in
            canvas.horizontalGradient(
                from: rgb(0x101820),
                to: rgb(0x9AA7B4),
                in: bounds
            )
            canvas.text(
                "Tekst over en glidende baggrund",
                at: NSPoint(x: 40, y: 250),
                font: .systemFont(ofSize: 32, weight: .semibold),
                color: .white,
                focus: "glidende"
            )
            canvas.text(
                "kræver lokal tærskel.",
                at: NSPoint(x: 40, y: 150),
                font: .systemFont(ofSize: 32, weight: .semibold),
                color: .white
            )
        }
    }

    private static func translucentPanel() throws -> OCRScenario {
        try scenario(
            name: "translucent-panel",
            axis: .background,
            expected: ["Teksten", "står", "på", "et", "panel"],
            focus: "panel"
        ) { canvas, bounds in
            canvas.fill(rgb(0x2B5D8A), bounds)
            canvas.fill(
                rgb(0xD2691E),
                NSRect(x: 0, y: 0, width: 320, height: bounds.height)
            )
            canvas.fill(
                rgb(0x1F7A4D),
                NSRect(x: 900, y: 0, width: 500, height: bounds.height)
            )
            canvas.fill(
                NSColor.white.withAlphaComponent(0.74),
                NSRect(x: 30, y: 90, width: 1_340, height: 250)
            )
            canvas.text(
                "Teksten står på et panel",
                at: NSPoint(x: 56, y: 240),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0x1A1A1C),
                focus: "panel"
            )
            canvas.text(
                "der er halvgennemsigtigt.",
                at: NSPoint(x: 56, y: 145),
                font: .systemFont(ofSize: 32, weight: .regular),
                color: rgb(0x1A1A1C)
            )
        }
    }

    // MARK: - Density

    private static func denseTableLight() throws -> OCRScenario {
        try scenario(
            name: "dense-table-light",
            axis: .density,
            expected: [
                "Månedlig", "leje", "møblering", "varmt", "vand",
                "indflytningsmåned"
            ],
            focus: "møblering"
        ) { canvas, bounds in
            canvas.fill(.white, bounds)
            drawTable(
                on: canvas,
                bounds: bounds,
                background: .white,
                rule: .black,
                textColor: .black
            )
        }
    }

    /// The same dense table inverted. A dark-on-light assumption anywhere in
    /// the small-text path erases this crop instead of reading it.
    private static func denseTableDark() throws -> OCRScenario {
        try scenario(
            name: "dense-table-dark",
            axis: .density,
            expected: [
                "Månedlig", "leje", "møblering", "varmt", "vand",
                "indflytningsmåned"
            ],
            focus: "møblering"
        ) { canvas, bounds in
            canvas.fill(rgb(0x16181D), bounds)
            drawTable(
                on: canvas,
                bounds: bounds,
                background: rgb(0x16181D),
                rule: rgb(0x8A8A93),
                textColor: rgb(0xD6D6DB)
            )
        }
    }

    private static func drawTable(
        on canvas: OCRScenarioCanvas,
        bounds: NSRect,
        background: NSColor,
        rule: NSColor,
        textColor: NSColor
    ) {
        let font = NSFont.systemFont(ofSize: 17, weight: .regular)
        let table = NSRect(x: 30, y: 110, width: 1_340, height: 120)
        canvas.stroke(rule, table)
        for x in [500.0, 950.0] {
            canvas.line(
                rule,
                from: NSPoint(x: x, y: table.minY),
                to: NSPoint(x: x, y: table.maxY)
            )
        }
        canvas.line(
            rule,
            from: NSPoint(x: table.minX, y: 170),
            to: NSPoint(x: table.maxX, y: 170)
        )
        canvas.text(
            "Månedlig leje inkl. evt. møblering",
            at: NSPoint(x: 42, y: 186),
            font: font,
            color: textColor,
            focus: "møblering"
        )
        canvas.text(
            "betaling for varme og varmt vand",
            at: NSPoint(x: 512, y: 186),
            font: font,
            color: textColor
        )
        canvas.text(
            "bidrag til drift",
            at: NSPoint(x: 962, y: 186),
            font: font,
            color: textColor
        )
        canvas.text(
            "Beboerindskud og depositum",
            at: NSPoint(x: 42, y: 128),
            font: font,
            color: textColor
        )
        canvas.text(
            "Ydelse for indflytningsmåned",
            at: NSPoint(x: 512, y: 128),
            font: font,
            color: textColor
        )
        canvas.text(
            "betaling for el",
            at: NSPoint(x: 962, y: 128),
            font: font,
            color: textColor
        )
        canvas.text(
            "Alle beløb er oplyst i kroner per måned.",
            at: NSPoint(x: 30, y: 280),
            font: NSFont.systemFont(ofSize: 26, weight: .regular),
            color: textColor
        )
    }

    // MARK: - Typography

    private static func trackedCapitals() throws -> OCRScenario {
        try scenario(
            name: "tracked-capitals",
            axis: .typography,
            expected: ["DANSKKURSER", "HOS", "A2B"],
            focus: "DANSKKURSER"
        ) { canvas, bounds in
            canvas.fill(.white, bounds)
            canvas.text(
                "DANSKKURSER HOS A2B",
                at: NSPoint(x: 48, y: 250),
                font: .systemFont(ofSize: 30, weight: .bold),
                color: rgb(0x101010),
                tracking: 5,
                focus: "DANSKKURSER"
            )
            canvas.text(
                "Undervisning i hele landet",
                at: NSPoint(x: 48, y: 150),
                font: .systemFont(ofSize: 28, weight: .regular),
                color: rgb(0x101010),
                tracking: 2
            )
        }
    }

    private static func italicSerif() throws -> OCRScenario {
        try scenario(
            name: "italic-serif",
            axis: .typography,
            expected: ["Kursiv", "skrift", "i", "en", "avisartikel"],
            focus: "avisartikel"
        ) { canvas, bounds in
            canvas.fill(rgb(0xFBF7EF), bounds)
            let serif = NSFont(name: "Times New Roman Italic", size: 34)
                ?? NSFontManager.shared.convert(
                    NSFont(name: "Times New Roman", size: 34)
                        ?? .systemFont(ofSize: 34),
                    toHaveTrait: .italicFontMask
                )
            canvas.text(
                "Kursiv skrift i en avisartikel",
                at: NSPoint(x: 48, y: 250),
                font: serif,
                color: rgb(0x1A1A1A),
                focus: "avisartikel"
            )
            canvas.text(
                "læses ofte langsommere.",
                at: NSPoint(x: 48, y: 160),
                font: serif,
                color: rgb(0x1A1A1A)
            )
        }
    }

    // MARK: - Rendering

    private static func scenario(
        name: String,
        axis: OCRScenario.Axis,
        expected: [String],
        focus: String,
        draw: (OCRScenarioCanvas, NSRect) -> Void
    ) throws -> OCRScenario {
        let width = Int(captureFrame.width * OCRScenarioCanvas.scale)
        let height = Int(captureFrame.height * OCRScenarioCanvas.scale)
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
            throw OCRScenarioError.bitmapCreationFailed
        }

        let canvas = OCRScenarioCanvas(captureFrame: captureFrame)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(
            canvas,
            NSRect(x: 0, y: 0, width: width, height: height)
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let image = bitmap.cgImage else {
            throw OCRScenarioError.imageCreationFailed
        }
        guard let focusPoint = canvas.focusPoint,
              canvas.recordedFocusWord() == focus else {
            throw OCRScenarioError.missingFocusWord(name)
        }

        return OCRScenario(
            name: name,
            axis: axis,
            image: image,
            captureFrame: captureFrame,
            screenFrame: screenFrame,
            displayID: displayID,
            expectedWords: expected,
            focusWord: focus,
            focusPoint: focusPoint
        )
    }

    private static func rgb(_ value: Int) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
