import AppKit
import SwiftUI
@testable import BabelstaarnetKit

/// The panel has to be a panel over whatever it lands on.
///
/// The reported fault was a grey background that sometimes did not show up.
/// The ground was `windowBackgroundColor`, chosen because a panel should be
/// painted whatever the system paints panels — but under Aqua that colour
/// resolves to pure white, which is also what an article page is. So over the
/// most ordinary page there is, the bubble's own ground was the page to the
/// pixel, and the only thing separating the answer from the text underneath
/// was whatever the material happened to sample from behind it. Over a sidebar
/// or a coloured block that was enough and the bubble read as a panel; over
/// body text it was nothing at all. The grey belonged to the page rather than
/// to the bubble, which is why it came and went with the page.
///
/// So what is checked is not which colour was chosen but whether the ground
/// still stands off the page: it is resolved in both appearances, laid over
/// the two pages that bound the range — a white article and a black one — at
/// the opacity the bubble actually paints it, and asked how far the result
/// moved from the page.
///
/// The material is left out and the page stands in for it, which is the worst
/// case rather than an approximation: the material only ever pulls the result
/// toward the page it is sampling, so a ground that separates here separates
/// on screen. That also puts `BubbleGround.opacity` inside the check — it is
/// documented as the one number to turn for more of the page showing through,
/// and this is the point past which turning it stops leaving a panel behind.
@main
@MainActor
enum BubbleGroundChecks {
    /// Below this the panel stops reading as a surface and starts reading as
    /// text lying loose on the page. The old ground scored 0.000 over white.
    static let leastVisibleStep: Double = 0.05

    static func main() {
        var weakest = (case: "", step: Double.greatestFiniteMagnitude)

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            guard let appearance = NSAppearance(named: appearanceName) else {
                preconditionFailure("No \(appearanceName.rawValue) appearance")
            }
            // The appearance is current only for the duration of the closure
            // and hands nothing back, so the ground is carried out of it.
            var ground: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                ground = NSColor(BubbleGround.color).usingColorSpace(.sRGB)
            }
            guard let ground else {
                preconditionFailure(
                    "The ground did not resolve in "
                        + appearanceName.rawValue
                )
            }

            for (pageName, page) in [
                ("white", NSColor.white),
                ("black", NSColor.black)
            ] {
                let label = "\(appearanceName.rawValue) over \(pageName)"
                guard let page = page.usingColorSpace(.sRGB) else {
                    preconditionFailure("No \(pageName) page")
                }
                let step = abs(
                    luminance(painted(ground, over: page))
                        - luminance(page)
                )
                precondition(
                    step >= leastVisibleStep,
                    "The bubble's ground is invisible \(label): painting it "
                        + "moves the page by \(step), and anything under "
                        + "\(leastVisibleStep) leaves the reader looking at "
                        + "text on the page rather than at a panel"
                )
                if step < weakest.step {
                    weakest = (label, step)
                }
            }
        }

        print(
            "Bubble ground checks passed "
                + "(weakest case \(weakest.case) at \(weakest.step))"
        )
    }

    /// The ground as the bubble paints it: over the page, at the opacity that
    /// lets some of the page back through.
    private static func painted(
        _ ground: NSColor,
        over page: NSColor
    ) -> NSColor {
        ground.blended(
            withFraction: 1 - BubbleGround.opacity,
            of: page
        ) ?? ground
    }

    private static func luminance(_ color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            preconditionFailure("Unresolvable colour")
        }
        return 0.2126 * srgb.redComponent
            + 0.7152 * srgb.greenComponent
            + 0.0722 * srgb.blueComponent
    }
}
