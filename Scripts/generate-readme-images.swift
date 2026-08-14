#!/usr/bin/env swift

// Renders the images the README shows: the app mark, and an illustration of
// the two bubbles over a Danish page.
//
// The illustration is drawn from the same constants the overlay uses — bubble
// widths, paddings, corner radii, type sizes and the rounded system face — so
// it stays a picture of the real design rather than an artist's impression of
// it. It is a rendering, not a screen capture: the translucent panel material
// cannot be reproduced offscreen, so it is stood in for by a near-opaque fill.

import AppKit
import Foundation
import SwiftUI

guard CommandLine.arguments.count == 2 else {
    fatalError("Expected an output directory.")
}

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

// MARK: - App mark

/// The same path the app icon is built from, so the README and the Dock agree.
func markPNG(pixels: Int, background: CGColor, stroke: CGColor) throws -> Data {
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
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.setShouldAntialias(true)

    context.setFillColor(background)
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
            cornerWidth: 224,
            cornerHeight: 224,
            transform: nil
        )
    )
    context.fillPath()

    context.setStrokeColor(stroke)
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

// MARK: - Illustration palette

struct Palette {
    let pageBackground: Color
    let sheet: Color
    let sheetStroke: Color
    let bodyText: Color
    let mutedText: Color
    let panel: Color
    let panelStroke: Color
    let primaryText: Color
    let secondaryText: Color
    let substitution: Color
    let control: Color
    let cursorFill: Color
    let cursorStroke: Color

    static let light = Palette(
        pageBackground: Color(red: 0.90, green: 0.90, blue: 0.89),
        sheet: .white,
        sheetStroke: Color.black.opacity(0.07),
        bodyText: Color(white: 0.16),
        mutedText: Color(white: 0.55),
        panel: Color(white: 0.985),
        panelStroke: Color.black.opacity(0.10),
        primaryText: Color(white: 0.11),
        secondaryText: Color(white: 0.42),
        substitution: Color.black.opacity(0.07),
        control: Color.black.opacity(0.06),
        cursorFill: .white,
        cursorStroke: Color(white: 0.12)
    )

    static let dark = Palette(
        pageBackground: Color(red: 0.11, green: 0.11, blue: 0.12),
        sheet: Color(white: 0.16),
        sheetStroke: Color.white.opacity(0.08),
        bodyText: Color(white: 0.90),
        mutedText: Color(white: 0.52),
        panel: Color(white: 0.235),
        panelStroke: Color.white.opacity(0.15),
        primaryText: Color(white: 0.97),
        secondaryText: Color(white: 0.70),
        substitution: Color.white.opacity(0.12),
        control: Color.white.opacity(0.10),
        cursorFill: Color(white: 0.14),
        cursorStroke: Color(white: 0.92)
    )
}

// MARK: - Illustration content
//
// One Danish line, read by someone who knows the everyday words and the
// function words but not the administrative ones. What they cannot read is
// replaced in place; Danish word order carries the sentence either way.

let danishLine = [
    "Ansøgningen", "skal", "indgives", "senest", "fire",
    "uger", "efter", "refleksionsperioden", "udløber.",
]
let hoveredWordIndex = 7

/// Danish stays Danish; only the words this reader cannot read are swapped.
let bridge: [(text: String, isEnglish: Bool)] = [
    ("The application", true),
    ("skal", false),
    ("be submitted", true),
    ("senest", false),
    ("fire", false),
    ("uger", false),
    ("efter", false),
    ("the period of reflection", true),
    ("expires.", true),
]

// MARK: - Pieces

struct Panel<Content: View>: View {
    let palette: Palette
    let width: CGFloat
    let cornerRadius: CGFloat
    let padding: EdgeInsets
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.panel)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                        .stroke(palette.panelStroke, lineWidth: 0.8)
                    }
            }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

/// The overlay's inline token layout: words flow and wrap as running text, so
/// a substitution several words long does not push the line off the panel.
struct WrappingRow: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        measure(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let measurement = measure(
            proposal: ProposedViewSize(
                width: bounds.width,
                height: proposal.height
            ),
            subviews: subviews
        )
        for (index, origin) in measurement.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func measure(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, origins: [CGPoint]) {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }

        return (
            CGSize(
                width: proposal.width ?? usedWidth,
                height: subviews.isEmpty ? 0 : y + rowHeight
            ),
            origins
        )
    }
}

/// The four controls, in the order their keys run.
struct ControlRow: View {
    let palette: Palette

    private let controls = [
        ("1", "Knew"), ("2", "Don’t know"), ("3", "Pin"), ("4", "All ENG"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(controls, id: \.0) { shortcut, title in
                HStack(spacing: 4) {
                    Text(shortcut)
                    Text(title)
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background { Capsule().fill(palette.control) }
            }
        }
    }
}

/// English set in the line, typed like the words beside it, with only a faint
/// tint to say it stood in for something.
struct BridgeLine: View {
    let palette: Palette

    var body: some View {
        WrappingRow(spacing: 4, lineSpacing: 4) {
            ForEach(Array(bridge.enumerated()), id: \.offset) { _, unit in
                if unit.isEnglish {
                    Text(unit.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(palette.substitution)
                        }
                } else {
                    Text(unit.text)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(palette.primaryText)
                }
            }
        }
    }
}

struct WordPanel: View {
    let palette: Palette

    var body: some View {
        Panel(
            palette: palette,
            width: 280,
            cornerRadius: 12,
            padding: EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ControlRow(palette: palette)
                Rectangle()
                    .fill(palette.panelStroke)
                    .frame(height: 0.8)

                Text("the period of reflection")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.primaryText)

                HStack(spacing: 5) {
                    Text("refleksionsperioden")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.mutedText)
                }

                Text("Den tid du har til at consider en beslutning.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SentencePanel: View {
    let palette: Palette

    var body: some View {
        Panel(
            palette: palette,
            width: 420,
            cornerRadius: 14,
            padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        ) {
            BridgeLine(palette: palette)
        }
    }
}

/// The macOS arrow, so it is clear the bubbles follow a pointer rather than a
/// selection.
struct Pointer: View {
    let palette: Palette

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 16.5))
            path.addLine(to: CGPoint(x: 4.1, y: 12.6))
            path.addLine(to: CGPoint(x: 6.8, y: 18.6))
            path.addLine(to: CGPoint(x: 9.6, y: 17.3))
            path.addLine(to: CGPoint(x: 6.9, y: 11.5))
            path.addLine(to: CGPoint(x: 12.2, y: 11.3))
            path.closeSubpath()
        }
        .fill(palette.cursorFill)
        .overlay {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 16.5))
                path.addLine(to: CGPoint(x: 4.1, y: 12.6))
                path.addLine(to: CGPoint(x: 6.8, y: 18.6))
                path.addLine(to: CGPoint(x: 9.6, y: 17.3))
                path.addLine(to: CGPoint(x: 6.9, y: 11.5))
                path.addLine(to: CGPoint(x: 12.2, y: 11.3))
                path.closeSubpath()
            }
            .stroke(palette.cursorStroke, lineWidth: 1.1)
        }
        .frame(width: 13, height: 19, alignment: .topLeading)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// The page underneath: an ordinary official-looking Danish document, which is
/// the situation the app is for.
struct SourceSheet: View {
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Vejledning til ansøgere")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.bodyText)

            Text(
                "Sagsbehandlingen begynder, når kontoret har modtaget "
                    + "dokumentationen."
            )
            .font(.system(size: 12.5))
            .foregroundStyle(palette.bodyText)

            // The overlay never marks up the page — it is a nonactivating
            // window over it — so nothing here is highlighted. Only the
            // pointer says which word is being answered.
            HStack(spacing: 4.5) {
                ForEach(Array(danishLine.enumerated()), id: \.offset) {
                    index, word in
                    Text(word)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.bodyText)
                        .anchorPreference(
                            key: HoveredWordAnchor.self,
                            value: .bounds
                        ) { index == hoveredWordIndex ? $0 : nil }
                }
            }

            Text(
                "Fristen kan ikke forlænges, og en ny ansøgning skal "
                    + "vedlægges dokumentation."
            )
            .font(.system(size: 12.5))
            .foregroundStyle(palette.bodyText)

            Text("Se afsnit 4 om klageadgang.")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.mutedText)
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 34, trailing: 24))
        .frame(width: 640, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.sheet)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.sheetStroke, lineWidth: 0.8)
                }
        }
    }
}

/// Where the hovered word sits, so the bubbles can be placed against it rather
/// than against numbers tuned by eye.
struct HoveredWordAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(
        value: inout Anchor<CGRect>?,
        nextValue: () -> Anchor<CGRect>?
    ) {
        value = value ?? nextValue()
    }
}

struct Illustration: View {
    let palette: Palette

    // Sized to the bubbles rather than to the page: the word panel is the tall
    // one, so it sets the room needed above the line.
    private let size = CGSize(width: 880, height: 302)
    private let gap: CGFloat = 10

    var body: some View {
        ZStack {
            palette.pageBackground
            SourceSheet(palette: palette).offset(y: 18)
        }
        .frame(width: size.width, height: size.height)
        .overlayPreferenceValue(HoveredWordAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let word = proxy[anchor]
                    let above = max(word.minY - gap, 0)
                    let below = max(size.height - word.maxY - gap, 0)

                    // The word panel hangs above the word and the sentence
                    // panel sits under it, both centred on it — the placement
                    // the overlay resolves to when there is room on both sides.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        WordPanel(palette: palette)
                    }
                    .frame(width: 280, height: above, alignment: .bottom)
                    .position(x: word.midX, y: above / 2)

                    VStack(spacing: 0) {
                        SentencePanel(palette: palette)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 420, height: below, alignment: .top)
                    .position(x: word.midX, y: size.height - below / 2)

                    Pointer(palette: palette)
                        .position(x: word.midX + 6.5, y: word.midY + 9.5)
                }
            }
        }
    }
}

// MARK: - Render

@MainActor
func writePNG(_ view: some View, to url: URL, scale: CGFloat = 2) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

try MainActor.assumeIsolated {
    try markPNG(
        pixels: 512,
        background: CGColor(red: 0.957, green: 0.957, blue: 0.957, alpha: 1),
        stroke: CGColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
    )
    .write(
        to: outputDirectory.appendingPathComponent("logo.png"),
        options: .atomic
    )

    try markPNG(
        pixels: 512,
        background: CGColor(red: 0.153, green: 0.153, blue: 0.161, alpha: 1),
        stroke: CGColor(red: 0.937, green: 0.937, blue: 0.937, alpha: 1)
    )
    .write(
        to: outputDirectory.appendingPathComponent("logo-dark.png"),
        options: .atomic
    )

    try writePNG(
        Illustration(palette: .light).environment(\.colorScheme, .light),
        to: outputDirectory.appendingPathComponent("hover-light.png")
    )

    try writePNG(
        Illustration(palette: .dark).environment(\.colorScheme, .dark),
        to: outputDirectory.appendingPathComponent("hover-dark.png")
    )
}

print("Wrote README images to \(outputDirectory.path)")
