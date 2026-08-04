import CoreGraphics
import Foundation

enum OCRRoutingPolicy {
    static let minimumFastVisionConfidence: Float = 0.45
    static let minimumFastVisionWordHeight: CGFloat = 9

    static func canUseFastVision(
        regions: [TextRegion],
        confidenceByRegionID: [UUID: Float],
        focusPoint: CGPoint?
    ) -> Bool {
        guard let focusPoint else {
            return false
        }

        return regions.contains { region in
            guard (confidenceByRegionID[region.id] ?? 0)
                >= minimumFastVisionConfidence else {
                return false
            }
            return region.words.contains { word in
                word.sourceText.count > 1
                    && word.frame.height >= minimumFastVisionWordHeight
                    && word.frame
                        .insetBy(dx: -4, dy: -5)
                        .contains(focusPoint)
            }
        }
    }
}
