import CoreGraphics
import Foundation

enum FocusedRegionSelectionPolicy {
    static func foregroundRegions(
        from regions: [TextRegion],
        at focusPoint: CGPoint
    ) -> [TextRegion] {
        let matches = regions.compactMap { region -> (TextRegion, CGFloat)? in
            let words = region.words.filter {
                $0.frame.insetBy(dx: -4, dy: -5).contains(focusPoint)
            }
            guard let nearest = words.min(by: {
                distance(from: $0.frame.center, to: focusPoint)
                    < distance(from: $1.frame.center, to: focusPoint)
            }) else {
                return nil
            }
            return (
                region,
                distance(from: nearest.frame.center, to: focusPoint)
            )
        }
        guard let match = matches.min(by: { $0.1 < $1.1 }) else {
            return regions
        }
        return [match.0]
    }

    static func focusedSourceKeys(
        in regions: [TextRegion],
        at focusPoint: CGPoint
    ) -> Set<String> {
        Set(
            regions
                .flatMap(\.words)
                .filter {
                    $0.frame
                        .insetBy(dx: -4, dy: -5)
                        .contains(focusPoint)
                }
                .map {
                    $0.sourceText.lowercased(
                        with: Locale(identifier: "da_DK")
                    )
                }
        )
    }

    private static func distance(
        from lhs: CGPoint,
        to rhs: CGPoint
    ) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
