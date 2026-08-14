import CoreGraphics
import Foundation

enum HoverHitTesting {
    /// A previous word, addressed the way a match looks it up: same display,
    /// same word.
    private struct WordKey: Hashable {
        let displayID: CGDirectDisplayID
        let text: String
    }

    static func stabilizeIdentifiers(
        in regions: [TextRegion],
        against previousRegions: [TextRegion]
    ) -> [TextRegion] {
        let previousWords = previousRegions.flatMap(\.words)
        guard !previousWords.isEmpty else {
            return regions
        }

        // The previous scan is indexed once, rather than scanned once per word.
        // Filtering the whole previous array for every new word copied it that
        // many times and re-normalized every candidate's text inside the
        // comparison, so the cost grew with the product of the two scans: a
        // pointer resting on blank space keeps the entire page — the hovered
        // line is only ever narrowed away when a word is actually under the
        // pointer — and 840 words then took two thirds of a second on the main
        // actor, which is the thread the bubble is drawn on.
        var indexByID: [UUID: Int] = [:]
        var indexesByWord: [WordKey: [Int]] = [:]
        indexByID.reserveCapacity(previousWords.count)
        for (index, previous) in previousWords.enumerated() {
            // First occurrence wins, matching the linear search this replaces.
            if indexByID[previous.id] == nil {
                indexByID[previous.id] = index
            }
            indexesByWord[
                WordKey(
                    displayID: previous.displayID,
                    text: normalized(previous.sourceText)
                ),
                default: []
            ].append(index)
        }

        var claimed = [Bool](repeating: false, count: previousWords.count)
        return regions.map { region in
            var updatedRegion = region
            updatedRegion.words = region.words.map { word in
                guard let match = replacementIndex(
                    for: word,
                    in: previousWords,
                    indexByID: indexByID,
                    indexesByWord: indexesByWord,
                    claimed: claimed
                ) else {
                    return word
                }
                claimed[match] = true
                return WordRegion(
                    id: previousWords[match].id,
                    sourceText: word.sourceText,
                    translatedText: word.translatedText,
                    wordBridgeDanishText: word.wordBridgeDanishText,
                    wordBridgeTranslations: word.wordBridgeTranslations,
                    wordBridgeText: word.wordBridgeText,
                    wordBridgeEnglishTokenIndexes:
                        word.wordBridgeEnglishTokenIndexes,
                    frame: word.frame,
                    screenFrame: word.screenFrame,
                    displayID: word.displayID
                )
            }
            return updatedRegion
        }
    }

    /// `replacement(for:in:)` against the index built above, and answering with
    /// a position so the caller can mark it taken.
    private static func replacementIndex(
        for word: WordRegion,
        in previousWords: [WordRegion],
        indexByID: [UUID: Int],
        indexesByWord: [WordKey: [Int]],
        claimed: [Bool]
    ) -> Int? {
        if let index = indexByID[word.id], !claimed[index] {
            return index
        }

        let key = WordKey(
            displayID: word.displayID,
            text: normalized(word.sourceText)
        )
        guard let candidates = indexesByWord[key] else {
            return nil
        }
        let center = word.frame.center
        var nearest: Int?
        var nearestDistance = CGFloat.infinity
        for index in candidates where !claimed[index] {
            let candidateDistance = distance(
                from: previousWords[index].frame.center,
                to: center
            )
            // Strictly nearer, so equal distances keep the earlier word — the
            // tie `min(by:)` broke the same way.
            if candidateDistance < nearestDistance {
                nearestDistance = candidateDistance
                nearest = index
            }
        }
        guard let nearest else {
            return nil
        }
        let tolerance = max(36, word.frame.height * 3)
        return nearestDistance <= tolerance ? nearest : nil
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

        // Normalizing the word being matched is loop-invariant; inside the
        // comparison it ran once per candidate, on a path the mouse timer
        // enters twenty times a second.
        let key = normalized(word.sourceText)
        let center = word.frame.center
        let nearest = candidates
            .filter {
                $0.displayID == word.displayID
                    && normalized($0.sourceText) == key
            }
            .min {
                distance(from: $0.frame.center, to: center)
                    < distance(from: $1.frame.center, to: center)
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
