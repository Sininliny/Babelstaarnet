import BabelCore
import CoreGraphics
import Foundation

/// The sentence a hovered word belongs to, gathered from however many OCR
/// lines it happens to be printed across.
///
/// Vision hands back one visual line at a time, and a line is not a sentence —
/// it is wherever the column happened to wrap. Bridging a line on its own gave
/// the reader "Ability i digital learning environments, including.": a
/// fragment that begins after the subject and stops before the verb, which
/// teaches neither the grammar it was meant to preserve nor the meaning the
/// reader was asking about. The lines above and below are therefore pulled in
/// until an actual sentence stop is reached.
///
/// The walk is skipped whenever the hovered line already stops on the right
/// side of the word, so a sentence that fits on one line costs nothing extra —
/// including the words sent for translation, which are exactly the words of
/// the lines returned here.
struct SentenceAssemblyPolicy: Sendable {
    struct AssembledSentence: Equatable, Sendable {
        /// The sentence, with the line breaks closed up.
        let text: String
        /// Which occurrence of the hovered word inside `text` was pointed at.
        /// A sentence spanning lines can repeat a word, and the bridge has to
        /// answer about the one under the pointer.
        let focusOccurrence: Int
        /// The lines the sentence is printed on, in reading order.
        let lines: [TextRegion]
    }

    /// How far the walk goes in each direction before it gives up on finding a
    /// stop. A sentence needing more than this on either side is either very
    /// long or the stop was lost to OCR, and both are better served by a
    /// bounded fragment than by dragging a paragraph into the bubble.
    let maximumContinuationLines = 3

    private let language: SourceLanguage
    private let boundary: SentenceBoundary

    init(language: SourceLanguage) {
        self.language = language
        self.boundary = language.sentenceBoundary
    }

    private static let wordExpression = try! NSRegularExpression(
        pattern: #"[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*"#
    )

    /// The sentence around `word`, assembled across as many of `regions` as it
    /// is printed on.
    func sentence(
        containing word: WordRegion,
        in region: TextRegion,
        among regions: [TextRegion]
    ) -> AssembledSentence {
        let hoveredText = compact(region.sourceText)
        guard let focusRange = range(of: word, in: region, text: hoveredText)
        else {
            return AssembledSentence(
                text: hoveredText,
                focusOccurrence: 0,
                lines: [region]
            )
        }

        let lines = self.lines(
            around: region,
            focusRange: focusRange,
            hoveredText: hoveredText,
            in: regions
        )
        let texts = lines.map { compact($0.sourceText) }
        let hoveredIndex = lines.firstIndex { $0.id == region.id } ?? 0
        let offset = texts[..<hoveredIndex].reduce(0) {
            $0 + ($1 as NSString).length + 1
        }
        let joined = texts.joined(separator: " ")
        let focusLocation = offset + focusRange.location
        let sentenceRange = boundary.sentenceRange(
            in: joined,
            containing: focusLocation
        )
        let text = (joined as NSString)
            .substring(with: sentenceRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AssembledSentence(
            text: text,
            focusOccurrence: occurrence(
                of: word.sourceText,
                in: joined,
                within: sentenceRange,
                at: focusLocation
            ),
            lines: lines
        )
    }

    /// The lines the sentence around `word` is printed on. This is what the
    /// scan keeps and translates, so it stays deliberately in step with what
    /// `sentence(containing:in:among:)` will later read.
    func lines(
        containing word: WordRegion,
        in region: TextRegion,
        among regions: [TextRegion]
    ) -> [TextRegion] {
        let hoveredText = compact(region.sourceText)
        guard let focusRange = range(of: word, in: region, text: hoveredText)
        else {
            return [region]
        }
        return lines(
            around: region,
            focusRange: focusRange,
            hoveredText: hoveredText,
            in: regions
        )
    }

    private func lines(
        around region: TextRegion,
        focusRange: NSRange,
        hoveredText: String,
        in regions: [TextRegion]
    ) -> [TextRegion] {
        let stops = boundary.stopLocations(in: hoveredText)
        var lines = [region]
        var used: Set<UUID> = [region.id]

        if !stops.contains(where: { $0 <= focusRange.location }) {
            var added = 0
            while added < maximumContinuationLines,
                  let above = neighbour(
                    of: lines[0],
                    above: true,
                    in: regions,
                    excluding: used
                  ) {
                used.insert(above.id)
                let text = compact(above.sourceText)
                guard !boundary.endsSentence(text) else {
                    break
                }
                lines.insert(above, at: 0)
                added += 1
                if boundary.stopsBeforeEnd(text) {
                    break
                }
            }
        }

        if !stops.contains(where: { $0 >= NSMaxRange(focusRange) }) {
            var added = 0
            while added < maximumContinuationLines,
                  let last = lines.last,
                  !boundary.endsSentence(
                    compact(last.sourceText)
                  ),
                  let below = neighbour(
                    of: last,
                    above: false,
                    in: regions,
                    excluding: used
                  ) {
                used.insert(below.id)
                lines.append(below)
                added += 1
                if boundary.stopsBeforeEnd(
                    compact(below.sourceText)
                ) {
                    break
                }
            }
        }
        return lines
    }

    /// The nearest line directly above or below `line` that reads as the same
    /// running text.
    private func neighbour(
        of line: TextRegion,
        above: Bool,
        in regions: [TextRegion],
        excluding used: Set<UUID>
    ) -> TextRegion? {
        regions
            .filter { candidate in
                guard !used.contains(candidate.id),
                      candidate.displayID == line.displayID,
                      above
                        ? candidate.frame.midY > line.frame.midY
                        : candidate.frame.midY < line.frame.midY else {
                    return false
                }
                return continuesLine(
                    upper: above ? candidate : line,
                    lower: above ? line : candidate
                )
            }
            .min {
                abs($0.frame.midY - line.frame.midY)
                    < abs($1.frame.midY - line.frame.midY)
            }
    }

    /// Whether two lines belong to the same run of text.
    ///
    /// Three things separate a wrapped line from the next thing on the page: a
    /// gap no wider than a line, a column the text shares, and type of the same
    /// size. The last one is what keeps a heading out of the paragraph beneath
    /// it, where the first two alone would have accepted it.
    private func continuesLine(
        upper: TextRegion,
        lower: TextRegion
    ) -> Bool {
        let upperFrame = upper.frame
        let lowerFrame = lower.frame
        guard upperFrame.height > 0, lowerFrame.height > 0 else {
            return false
        }

        let lineHeight = max(upperFrame.height, lowerFrame.height)
        let gap = upperFrame.minY - lowerFrame.maxY
        guard gap <= lineHeight * 1.25, gap >= -lineHeight * 0.6 else {
            return false
        }

        let overlap = min(upperFrame.maxX, lowerFrame.maxX)
            - max(upperFrame.minX, lowerFrame.minX)
        let narrower = min(upperFrame.width, lowerFrame.width)
        guard narrower > 0, overlap >= narrower * 0.4 else {
            return false
        }

        // Vision reports a box that follows whichever ascenders and descenders
        // the line happens to contain, so same-size type still varies by a
        // fifth or so either way.
        let ratio = upperFrame.height / lowerFrame.height
        return ratio >= 0.7 && ratio <= 1.45
    }

    /// Where `word` sits in its own line, counted by occurrence so a line
    /// repeating the word still resolves to the one under the pointer.
    private func range(
        of word: WordRegion,
        in region: TextRegion,
        text: String
    ) -> NSRange? {
        let key = normalized(word.sourceText)
        guard !key.isEmpty else {
            return nil
        }
        let index = region.words.firstIndex { $0.id == word.id }
            ?? region.words.count
        let occurrence = region.words[..<index].filter {
            normalized($0.sourceText) == key
        }.count
        let source = text as NSString
        let matches = wordMatches(in: text).filter {
            normalized(source.substring(with: $0)) == key
        }
        guard !matches.isEmpty else {
            return nil
        }
        return matches[min(occurrence, matches.count - 1)]
    }

    private func occurrence(
        of word: String,
        in text: String,
        within sentence: NSRange,
        at location: Int
    ) -> Int {
        let key = normalized(word)
        guard !key.isEmpty else {
            return 0
        }
        let source = text as NSString
        return wordMatches(in: text).filter { range in
            range.location >= sentence.location
                && range.location < location
                && normalized(source.substring(with: range)) == key
        }.count
    }

    private func wordMatches(in text: String) -> [NSRange] {
        Self.wordExpression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).map(\.range)
    }

    private func normalized(_ word: String) -> String {
        language.normalized(word)
    }

    private func compact(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
