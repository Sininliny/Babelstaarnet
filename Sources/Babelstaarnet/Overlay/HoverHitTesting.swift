import CoreGraphics
import Foundation

enum HoverHitTesting {
    static func stabilizeIdentifiers(
        in regions: [TextRegion],
        against previousRegions: [TextRegion]
    ) -> [TextRegion] {
        let previousWords = previousRegions.flatMap(\.words)
        guard !previousWords.isEmpty else {
            return regions
        }

        var usedIDs = Set<UUID>()
        return regions.map { region in
            var updatedRegion = region
            updatedRegion.words = region.words.map { word in
                let candidates = previousWords.filter {
                    !usedIDs.contains($0.id)
                }
                guard let match = replacement(for: word, in: candidates) else {
                    return word
                }
                usedIDs.insert(match.id)
                return WordRegion(
                    id: match.id,
                    sourceText: word.sourceText,
                    translatedText: word.translatedText,
                    beginnerExplanation: word.beginnerExplanation,
                    adaptiveExplanation: word.adaptiveExplanation,
                    adaptiveEnglishTerms: word.adaptiveEnglishTerms,
                    frame: word.frame,
                    screenFrame: word.screenFrame,
                    displayID: word.displayID
                )
            }
            return updatedRegion
        }
    }

    static func word(
        at point: CGPoint,
        in regions: [TextRegion],
        retaining current: WordRegion?
    ) -> WordRegion? {
        let words = regions.flatMap(\.words)
        let currentReplacement = current.flatMap {
            replacement(for: $0, in: words)
        }

        let directCandidates = words.filter {
            $0.frame.insetBy(dx: -4, dy: -5).contains(point)
        }

        if let currentReplacement {
            if let enteredNeighbor = directCandidates
                .filter({ !representsSameTarget($0, currentReplacement) })
                .filter({ $0.frame.contains(point) })
                .min(by: { distance(from: point, to: $0.frame.center)
                    < distance(from: point, to: $1.frame.center) }) {
                return enteredNeighbor
            }

            if retentionFrame(for: currentReplacement).contains(point) {
                return currentReplacement
            }
        }

        return directCandidates.min {
            let leftDistance = distance(from: point, to: $0.frame.center)
            let rightDistance = distance(from: point, to: $1.frame.center)
            if abs(leftDistance - rightDistance) > 0.5 {
                return leftDistance < rightDistance
            }
            return $0.frame.area < $1.frame.area
        }
    }

    static func replacement(
        for word: WordRegion,
        in candidates: [WordRegion]
    ) -> WordRegion? {
        if let identical = candidates.first(where: { $0.id == word.id }) {
            return identical
        }

        let nearest = candidates
            .filter {
                $0.displayID == word.displayID
                    && normalized($0.sourceText) == normalized(word.sourceText)
            }
            .min {
                distance(from: $0.frame.center, to: word.frame.center)
                    < distance(from: $1.frame.center, to: word.frame.center)
            }

        guard let nearest else {
            return nil
        }
        let tolerance = max(36, word.frame.height * 3)
        return distance(from: nearest.frame.center, to: word.frame.center)
            <= tolerance ? nearest : nil
    }

    static func representsSameTarget(
        _ lhs: WordRegion?,
        _ rhs: WordRegion?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            if lhs.id == rhs.id {
                return true
            }
            guard lhs.displayID == rhs.displayID,
                  normalized(lhs.sourceText) == normalized(rhs.sourceText) else {
                return false
            }
            let tolerance = max(36, max(lhs.frame.height, rhs.frame.height) * 3)
            return distance(from: lhs.frame.center, to: rhs.frame.center)
                <= tolerance
        default:
            return false
        }
    }

    private static func retentionFrame(for word: WordRegion) -> CGRect {
        let horizontal = max(10, word.frame.height * 0.55)
        let vertical = max(8, word.frame.height * 0.5)
        return word.frame.insetBy(dx: -horizontal, dy: -vertical)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
                    .union(.punctuationCharacters)
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

    var area: CGFloat {
        width * height
    }
}
