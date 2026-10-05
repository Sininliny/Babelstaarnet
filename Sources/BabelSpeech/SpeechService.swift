import AVFoundation

/// How good a voice is, in the order the synthesizer ranks them.
public enum SpeechVoiceQuality: Int, Comparable, Sendable {
    case basic = 1
    case enhanced = 2
    case premium = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the choice of voice depends on, apart from the voice itself.
///
/// Kept separate from `AVSpeechSynthesisVoice`, which cannot be made with
/// chosen properties, so the ranking can be checked without whichever voices
/// the machine running the checks happens to have installed.
public struct SpeechVoiceCandidate: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let language: String
    public let quality: SpeechVoiceQuality
    /// Novelty voices — the bells, the whisper — and the reader's own
    /// Personal Voice are installed alongside the real ones and are never an
    /// answer to "how is this word pronounced".
    public let isSpecialPurpose: Bool

    public init(
        identifier: String,
        name: String,
        language: String,
        quality: SpeechVoiceQuality,
        isSpecialPurpose: Bool = false
    ) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.quality = quality
        self.isSpecialPurpose = isSpecialPurpose
    }

    /// The best installed voice for a language.
    ///
    /// `AVSpeechSynthesisVoice(language:)` answers with the system default,
    /// which for Danish is the compact voice every Mac ships with, whether or
    /// not a better one has been downloaded. The reader who went to the
    /// trouble of downloading an enhanced voice was still hearing the compact
    /// one. Quality decides first; the exact region then breaks a tie over a
    /// voice that only shares the language.
    public static func best(
        for language: String,
        among candidates: [SpeechVoiceCandidate]
    ) -> SpeechVoiceCandidate? {
        let wanted = normalized(language)
        let base = wanted.split(separator: "-").first.map(String.init) ?? wanted
        return candidates
            .filter { !$0.isSpecialPurpose }
            .filter {
                let candidate = normalized($0.language)
                return candidate == wanted
                    || candidate == base
                    || candidate.hasPrefix(base + "-")
            }
            .max { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality < rhs.quality
                }
                let lhsExact = normalized(lhs.language) == wanted
                let rhsExact = normalized(rhs.language) == wanted
                if lhsExact != rhsExact {
                    return !lhsExact
                }
                // A stable answer between two equal voices, so the one that
                // speaks does not depend on the order the system lists them.
                return lhs.identifier > rhs.identifier
            }
    }

    private static func normalized(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

@MainActor
public final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    /// The voice for a language, kept once it has been found.
    ///
    /// Resolving one searches the installed voices, and it was being resolved
    /// again for every word a reader settled on — on the main actor, in the
    /// same instant the bubble is being drawn. The installed voices change only
    /// when the reader downloads or removes one, which the system announces,
    /// so the cache is dropped then and not otherwise.
    private var voicesByLanguage: [String: AVSpeechSynthesisVoice?] = [:]
    private var voicesObserver: NSObjectProtocol?

    public init() {
        voicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.voicesByLanguage.removeAll()
            }
        }
    }

    deinit {
        if let voicesObserver {
            NotificationCenter.default.removeObserver(voicesObserver)
        }
    }

    public func speak(_ text: String, language: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        utterance.rate = 0.43
        synthesizer.speak(utterance)
    }

    /// The voice a word in this language will be spoken with, for the reader
    /// to be told about — and told when a better one is a download away.
    public func installedVoice(for language: String) -> SpeechVoiceCandidate? {
        voice(for: language).map(Self.candidate(for:))
    }

    private func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if let known = voicesByLanguage[language] {
            return known
        }
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let best = SpeechVoiceCandidate.best(
            for: language,
            among: installed.map(Self.candidate(for:))
        )
        let resolved = best.flatMap { chosen in
            installed.first { $0.identifier == chosen.identifier }
        } ?? AVSpeechSynthesisVoice(language: language)
        voicesByLanguage[language] = resolved
        return resolved
    }

    private static func candidate(
        for voice: AVSpeechSynthesisVoice
    ) -> SpeechVoiceCandidate {
        SpeechVoiceCandidate(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: SpeechVoiceQuality(rawValue: voice.quality.rawValue)
                ?? .basic,
            isSpecialPurpose: voice.voiceTraits.contains(.isNoveltyVoice)
                || voice.voiceTraits.contains(.isPersonalVoice)
        )
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
