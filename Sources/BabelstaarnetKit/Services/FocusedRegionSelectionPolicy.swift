import BabelCore
import CoreGraphics
import Foundation

struct FocusedRegionSelectionPolicy: Sendable {
    private let language: SourceLanguage
    private let sentenceAssembly: SentenceAssemblyPolicy

    init(language: SourceLanguage) {
        self.language = language
        self.sentenceAssembly = SentenceAssemblyPolicy(language: language)
    }

    func foregroundRegions(
        from regions: [TextRegion],
        at focusPoint: CGPoint
    ) -> [TextRegion] {
        guard let match = focusedWord(in: regions, at: focusPoint) else {
            return regions
        }
        // The hovered line, plus the lines its sentence runs onto. Keeping the
        // line alone was cheaper, but it decided the bubble could only ever
        // show the fragment the column happened to wrap — and the words on the
        // continuation lines were dropped before translation, so nothing later
        // in the pipeline could recover them.
        return sentenceAssembly.lines(
            containing: match.word,
            in: match.region,
            among: regions
        )
    }

    /// The word under the pointer and the line it is on, if the pointer is on
    /// a word at all.
    func focusedWord(
        in regions: [TextRegion],
        at focusPoint: CGPoint
    ) -> (region: TextRegion, word: WordRegion)? {
        let matches = regions.compactMap {
            region -> (TextRegion, WordRegion, CGFloat)? in
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
                nearest,
                distance(from: nearest.frame.center, to: focusPoint)
            )
        }
        return matches.min(by: { $0.2 < $1.2 }).map {
            (region: $0.0, word: $0.1)
        }
    }

    func focusedSourceKeys(
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
                .map { language.lowercased($0.sourceText) }
        )
    }

    private func distance(
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
