import CoreGraphics
import Foundation

@main
enum SentenceAssemblyChecks {
    private static let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    static func main() {
        // The reported page: a sentence wrapped across three column lines,
        // with the pointer on a word in the middle one. What the bubble showed
        // before was the middle line alone.
        let first = line(
            "Det kunne fx være oplysningskampagner, støtte til",
            top: 600
        )
        let second = line(
            "underrepræsenterede grupper, tilgængelighed i digitale",
            top: 570
        )
        let third = line(
            "læringsmiljøer og lige adgang til mobilitetsmidler.",
            top: 540
        )
        let next = line(
            "Andre emner er også velkomne.",
            top: 510
        )
        let page = [first, second, third, next]

        let assembled = SentenceAssemblyPolicy.sentence(
            containing: word("digitale", in: second),
            in: second,
            among: page
        )
        precondition(
            assembled.text
                == "Det kunne fx være oplysningskampagner, støtte til"
                + " underrepræsenterede grupper, tilgængelighed i digitale"
                + " læringsmiljøer og lige adgang til mobilitetsmidler.",
            assembled.text
        )
        precondition(assembled.lines == [first, second, third], "lines")
        precondition(assembled.focusOccurrence == 0)

        // The sentence after it stands on its own line and pulls in nothing:
        // the line it is printed on already stops on both sides of the word.
        let standalone = SentenceAssemblyPolicy.sentence(
            containing: word("emner", in: next),
            in: next,
            among: page
        )
        precondition(
            standalone.text == "Andre emner er også velkomne.",
            standalone.text
        )
        precondition(standalone.lines == [next])

        // A line carrying the end of one sentence and the start of another
        // gives up only the half the pointer is in.
        let opening = line("Fristen er fast. Emnerne kan spænde", top: 300)
        let closing = line("bredt over mange fag.", top: 270)
        let mixed = SentenceAssemblyPolicy.sentence(
            containing: word("spænde", in: opening),
            in: opening,
            among: [opening, closing]
        )
        precondition(
            mixed.text == "Emnerne kan spænde bredt over mange fag.",
            mixed.text
        )
        precondition(mixed.lines == [opening, closing])

        let ending = SentenceAssemblyPolicy.sentence(
            containing: word("Fristen", in: opening),
            in: opening,
            among: [opening, closing]
        )
        precondition(ending.text == "Fristen er fast.", ending.text)
        precondition(ending.lines == [opening])

        // A heading sits directly above the paragraph with the same column and
        // spacing, and is kept out of it by its type size alone.
        let heading = line("Kom til infomøde", top: 200, height: 44)
        let body = line("Du kan høre mere om", top: 160)
        let underHeading = SentenceAssemblyPolicy.sentence(
            containing: word("høre", in: body),
            in: body,
            among: [heading, body]
        )
        precondition(
            underHeading.text == "Du kan høre mere om",
            underHeading.text
        )
        precondition(underHeading.lines == [body])

        // A second column beside the text is never a continuation of it.
        let leftColumn = line("Emnerne kan spænde bredt, og", top: 400)
        let rightColumn = line(
            "der er ansøgningsfrist til september",
            top: 370,
            left: 900
        )
        let columns = SentenceAssemblyPolicy.sentence(
            containing: word("spænde", in: leftColumn),
            in: leftColumn,
            among: [leftColumn, rightColumn]
        )
        precondition(columns.lines == [leftColumn], "columns")

        // A paragraph with no stop anywhere near stops the walk on its own
        // rather than swallowing the page.
        let runOn = (0..<9).map { index in
            line(
                "nogle ord uden punktum her \(index)",
                top: 800 - CGFloat(index) * 30
            )
        }
        let bounded = SentenceAssemblyPolicy.sentence(
            containing: word("uden", in: runOn[4]),
            in: runOn[4],
            among: runOn
        )
        precondition(
            bounded.lines.count
                <= SentenceAssemblyPolicy.maximumContinuationLines * 2 + 1,
            "\(bounded.lines.count)"
        )

        // A word repeated across the line break still resolves to the one
        // under the pointer, so the bridge answers about that occurrence.
        let repeatedFirst = line("Et land og et andet", top: 100)
        let repeatedSecond = line("land blev nævnt.", top: 70)
        let repeated = SentenceAssemblyPolicy.sentence(
            containing: word("land", in: repeatedSecond),
            in: repeatedSecond,
            among: [repeatedFirst, repeatedSecond]
        )
        precondition(
            repeated.text == "Et land og et andet land blev nævnt.",
            repeated.text
        )
        precondition(repeated.focusOccurrence == 1, "\(repeated.focusOccurrence)")

        print("Sentence assembly checks passed")
    }

    private static func line(
        _ text: String,
        top: CGFloat,
        left: CGFloat = 100,
        height: CGFloat = 24
    ) -> TextRegion {
        // Words are laid out left to right at a fixed advance, which is all the
        // geometry these checks need: the policy reads line boxes, and hit
        // testing has its own checks.
        var x = left
        var words: [WordRegion] = []
        for token in text.split(whereSeparator: \Character.isWhitespace) {
            let width = CGFloat(token.count) * 9
            words.append(
                WordRegion(
                    sourceText: String(token).trimmingCharacters(
                        in: .punctuationCharacters
                    ),
                    frame: CGRect(x: x, y: top, width: width, height: height),
                    screenFrame: screen,
                    displayID: 1
                )
            )
            x += width + 6
        }
        return TextRegion(
            sourceText: text,
            frame: CGRect(
                x: left,
                y: top,
                width: x - left - 6,
                height: height
            ),
            screenFrame: screen,
            displayID: 1,
            words: words
        )
    }

    private static func word(
        _ text: String,
        in region: TextRegion
    ) -> WordRegion {
        guard let match = region.words.first(where: {
            $0.sourceText.lowercased() == text.lowercased()
        }) else {
            preconditionFailure("\(text) is not in \(region.sourceText)")
        }
        return match
    }
}
