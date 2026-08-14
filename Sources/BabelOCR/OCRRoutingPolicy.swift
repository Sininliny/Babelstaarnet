import CoreGraphics
import Foundation
import BabelCore

enum OCRRoutingPolicy {
    static let minimumAccurateFocusedConfidence: Float = 0.35
    static let minimumAccurateFocusedWordHeight: CGFloat = 3

    /// Whether a Vision pass produced a word usable under the pointer, which is
    /// what decides between returning now and preparing the crop for a retry.
    static func canUseAccurateFocusedVision(
        regions: [TextRegion],
        confidenceByRegionID: [UUID: Float],
        focusPoint: CGPoint?
    ) -> Bool {
        guard let focusPoint else {
            return false
        }
        return regions.contains { region in
            guard (confidenceByRegionID[region.id] ?? 0)
                >= minimumAccurateFocusedConfidence else {
                return false
            }
            return region.words.contains { word in
                word.sourceText.count > 1
                    && word.frame.height
                        >= minimumAccurateFocusedWordHeight
                    && word.frame
                        .insetBy(dx: -4, dy: -5)
                        .contains(focusPoint)
            }
        }
    }
}
