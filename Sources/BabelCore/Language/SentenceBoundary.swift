import Foundation

/// Where one sentence stops and the next one starts.
///
/// A period is a weak signal in many languages. Ordinals carry one — "den 15.
/// september" — dates and list numbers carry one, and a language may
/// abbreviate heavily: "bl.a.", "ca.", "kl.", "f.eks.". Splitting on periods
/// alone cut "Der er ansøgningsfrist den 15." out of its own sentence.
///
/// What settles it is mostly what follows. Where a sentence opens with a
/// capital, a period followed by a lower-case word or by a digit is part of
/// the sentence rather than the end of it. The word in front of the period
/// decides the rest: a number is an ordinal, a known abbreviation is an
/// abbreviation, and a single letter is an initial.
///
/// The rules are supplied by the source language rather than written here,
/// because the capital-letter signal — the strongest one this has — is simply
/// unavailable in a script without case.
public struct SentenceBoundary: Sendable {
    private let rules: SentenceBoundaryRules
    private let locale: Locale

    public init(rules: SentenceBoundaryRules, locale: Locale) {
        self.rules = rules
        self.locale = locale
    }

    /// Where each sentence stop in `text` ends, as offsets into its UTF-16
    /// view. An offset is the first index *after* the stop and any closing
    /// quote or bracket that belongs to it.
    public func stopLocations(in text: String) -> [Int] {
        let source = text as NSString
        var locations: [Int] = []
        var index = 0
        while index < source.length {
            guard let end = stopEnd(at: index, in: source) else {
                index += 1
                continue
            }
            locations.append(end)
            index = end
        }
        return locations
    }

    /// Whether `text` runs all the way to a sentence stop.
    public func endsSentence(_ text: String) -> Bool {
        let source = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) as NSString
        guard source.length > 0 else {
            return false
        }
        var index = source.length - 1
        while index > 0,
              let closer = character(at: index, in: source),
              rules.closers.contains(closer) {
            index -= 1
        }
        return stopEnd(at: index, in: source) == source.length
    }

    /// Whether `text` stops somewhere other than at its own end, which is what
    /// tells a line walk that the sentence it is following ends inside this
    /// line and no further line is needed.
    public func stopsBeforeEnd(_ text: String) -> Bool {
        let length = (text as NSString).length
        return stopLocations(in: text).contains { $0 < length }
    }

    /// The sentences in `text`, as ranges over its UTF-16 view.
    public func sentenceRanges(in text: String) -> [NSRange] {
        let source = text as NSString
        var ranges: [NSRange] = []
        var start = 0
        for stop in stopLocations(in: text) where stop > start {
            ranges.append(NSRange(location: start, length: stop - start))
            var next = stop
            while next < source.length,
                  let space = character(at: next, in: source),
                  space.isWhitespace {
                next += 1
            }
            start = next
        }
        if start < source.length {
            ranges.append(
                NSRange(location: start, length: source.length - start)
            )
        }
        return ranges
    }

    /// The sentence `location` falls inside. Text that holds no stop at all is
    /// one sentence, which is the common case for a single OCR line.
    public func sentenceRange(
        in text: String,
        containing location: Int
    ) -> NSRange {
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        let ranges = sentenceRanges(in: text)
        guard ranges.count > 1 else {
            return ranges.first ?? whole
        }
        for range in ranges where location < NSMaxRange(range) {
            return range
        }
        return ranges.last ?? whole
    }

    /// The index just past a real sentence stop at `index`, or `nil` when the
    /// character there is not one, or is a period doing some other job.
    private func stopEnd(at index: Int, in source: NSString) -> Int? {
        guard let stop = character(at: index, in: source),
              rules.stops.contains(stop) else {
            return nil
        }

        var end = index + 1
        while end < source.length,
              let next = character(at: end, in: source),
              rules.stops.contains(next) || rules.closers.contains(next) {
            end += 1
        }

        if end < source.length {
            guard let next = character(at: end, in: source),
                  next.isWhitespace else {
                // "17.30", "bl.a", "www.au.dk": a stop with the next word
                // pressed against it is punctuation inside a token.
                return nil
            }
            var following = end
            while following < source.length,
                  let candidate = character(at: following, in: source),
                  candidate.isWhitespace || rules.openers.contains(candidate) {
                following += 1
            }
            if let next = character(at: following, in: source),
               next.isNumber || (rules.opensWithCapital && next.isLowercase) {
                // A sentence here opens with a capital, so this period is an
                // ordinal or an abbreviation the list below has not heard of —
                // "den 15. september", "kl. 13".
                return nil
            }
        }

        guard stop == "." else {
            return end
        }
        let stem = wordStem(before: index, in: source)
            .lowercased(with: locale)
        guard !stem.isEmpty else {
            return end
        }
        if stem.allSatisfy({ $0.isNumber || $0 == "." }) {
            return nil
        }
        if rules.abbreviations.contains(stem) {
            return nil
        }
        if rules.singleLetterIsInitial,
           stem.count == 1,
           stem.first?.isLetter == true {
            return nil
        }
        return end
    }

    /// The token in front of a period, interior periods included, so "bl.a."
    /// is read as one abbreviation rather than as the letter "a".
    private func wordStem(
        before index: Int,
        in source: NSString
    ) -> String {
        var start = index
        while start > 0 {
            guard let previous = character(at: start - 1, in: source),
                  previous.isLetter
                    || previous.isNumber
                    || previous == "." else {
                break
            }
            start -= 1
        }
        guard start < index else {
            return ""
        }
        return source.substring(with: NSRange(
            location: start,
            length: index - start
        ))
    }

    private func character(
        at index: Int,
        in source: NSString
    ) -> Character? {
        guard index >= 0, index < source.length else {
            return nil
        }
        let scalar = source.character(at: index)
        guard let unicode = UnicodeScalar(scalar) else {
            return nil
        }
        return Character(unicode)
    }
}

public extension SourceLanguage {
    /// This language's sentence boundary, ready to use.
    var sentenceBoundary: SentenceBoundary {
        SentenceBoundary(rules: sentenceRules, locale: locale)
    }
}
