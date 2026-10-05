import Foundation
@testable import BabelSpeech

@main
enum SpeechVoiceSelectionChecks {
    static func main() {
        let compact = SpeechVoiceCandidate(
            identifier: "com.apple.voice.compact.da-DK.Sara",
            name: "Sara",
            language: "da-DK",
            quality: .basic
        )
        let enhanced = SpeechVoiceCandidate(
            identifier: "com.apple.voice.enhanced.da-DK.Magnus",
            name: "Magnus",
            language: "da-DK",
            quality: .enhanced
        )
        let novelty = SpeechVoiceCandidate(
            identifier: "com.apple.speech.synthesis.voice.Bells",
            name: "Bells",
            language: "da-DK",
            quality: .premium,
            isSpecialPurpose: true
        )
        let english = SpeechVoiceCandidate(
            identifier: "com.apple.voice.premium.en-GB.Serena",
            name: "Serena",
            language: "en-GB",
            quality: .premium
        )

        // The system default is the compact voice; a downloaded enhanced one
        // has to win over it, or downloading it changed nothing.
        precondition(
            SpeechVoiceCandidate.best(
                for: "da-DK",
                among: [compact, enhanced, english]
            ) == enhanced
        )

        // A better voice in another language is not a Danish voice.
        precondition(
            SpeechVoiceCandidate.best(
                for: "da-DK",
                among: [compact, english]
            ) == compact
        )

        // Novelty and personal voices never pronounce a word.
        precondition(
            SpeechVoiceCandidate.best(
                for: "da-DK",
                among: [compact, novelty]
            ) == compact
        )

        // A voice that only shares the language is used when it is all there
        // is, and loses a tie to the exact region.
        let bare = SpeechVoiceCandidate(
            identifier: "z.bare",
            name: "Bare",
            language: "da",
            quality: .enhanced
        )
        precondition(
            SpeechVoiceCandidate.best(for: "da-DK", among: [bare]) == bare
        )
        precondition(
            SpeechVoiceCandidate.best(
                for: "da_DK",
                among: [bare, enhanced]
            ) == enhanced
        )

        // "da" must not match a language that merely starts with the letters.
        let dari = SpeechVoiceCandidate(
            identifier: "dari",
            name: "Dari",
            language: "dav-KE",
            quality: .premium
        )
        precondition(
            SpeechVoiceCandidate.best(for: "da-DK", among: [dari]) == nil
        )

        // The answer between equal voices does not depend on listing order.
        let other = SpeechVoiceCandidate(
            identifier: "com.apple.voice.enhanced.da-DK.Sara",
            name: "Sara",
            language: "da-DK",
            quality: .enhanced
        )
        precondition(
            SpeechVoiceCandidate.best(for: "da-DK", among: [enhanced, other])
                == SpeechVoiceCandidate.best(
                    for: "da-DK",
                    among: [other, enhanced]
                )
        )

        print("Speech voice selection checks passed")
    }
}
