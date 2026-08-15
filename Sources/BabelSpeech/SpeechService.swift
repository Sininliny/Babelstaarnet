import AVFoundation

@MainActor
public final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    /// The voice for a language, kept once it has been found.
    ///
    /// Resolving one searches the installed voices, and it was being resolved
    /// again for every word a reader settled on — on the main actor, in the
    /// same instant the bubble is being drawn. A language's voice does not
    /// change while the app is open.
    private var voicesByLanguage: [String: AVSpeechSynthesisVoice?] = [:]

    public init() {}

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

    private func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if let known = voicesByLanguage[language] {
            return known
        }
        let resolved = AVSpeechSynthesisVoice(language: language)
        voicesByLanguage[language] = resolved
        return resolved
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
