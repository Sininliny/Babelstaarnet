import CoreGraphics
import Foundation

enum TranslationMode: String, CaseIterable, Identifiable, Sendable {
    case english
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "Danish → English"
        case .none:
            return "None"
        }
    }

    var shortTitle: String {
        self == .english ? "English" : "No translation"
    }
}

enum ExplanationMode: String, CaseIterable, Identifiable, Sendable {
    case adaptive
    case beginner
    case easyDanish
    case english
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive:
            return "Adaptive"
        case .beginner:
            return "Beginner"
        case .easyDanish:
            return "Easy Danish"
        case .english:
            return "English"
        case .none:
            return "None"
        }
    }

    var badgeTitle: String? {
        nil
    }
}

struct CapturedDisplay: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    let image: CGImage
    let frame: CGRect
    let screenFrame: CGRect

    init(
        displayID: CGDirectDisplayID,
        image: CGImage,
        frame: CGRect,
        screenFrame: CGRect? = nil
    ) {
        self.displayID = displayID
        self.image = image
        self.frame = frame
        self.screenFrame = screenFrame ?? frame
    }
}

struct WordRegion: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceText: String
    var translatedText: String
    var beginnerExplanation: String
    var adaptiveExplanation: String
    var adaptiveEnglishTerms: [String]
    let frame: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String = "",
        beginnerExplanation: String = "",
        adaptiveExplanation: String = "",
        adaptiveEnglishTerms: [String] = [],
        frame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.beginnerExplanation = beginnerExplanation
        self.adaptiveExplanation = adaptiveExplanation
        self.adaptiveEnglishTerms = adaptiveEnglishTerms
        self.frame = frame
        self.screenFrame = screenFrame
        self.displayID = displayID
    }
}

struct TextRegion: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceText: String
    var translatedText: String
    let frame: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
    var words: [WordRegion]

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String = "",
        frame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID,
        words: [WordRegion]
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.frame = frame
        self.screenFrame = screenFrame
        self.displayID = displayID
        self.words = words
    }
}

struct HoverCard: Equatable, Sendable {
    let word: WordRegion
    let definition: String
    let englishSupport: String?
    let familiarityLabel: String?
    let englishIsExpanded: Bool
    let translationMode: TranslationMode
    let explanationMode: ExplanationMode

    init(
        word: WordRegion,
        definition: String,
        englishSupport: String? = nil,
        familiarityLabel: String? = nil,
        englishIsExpanded: Bool = false,
        translationMode: TranslationMode,
        explanationMode: ExplanationMode
    ) {
        self.word = word
        self.definition = definition
        self.englishSupport = englishSupport
        self.familiarityLabel = familiarityLabel
        self.englishIsExpanded = englishIsExpanded
        self.translationMode = translationMode
        self.explanationMode = explanationMode
    }
}

enum ScanPhase: Equatable {
    case idle
    case capturing
    case recognizing
    case translating
    case showing(regionCount: Int)
    case failed(message: String)

    var label: String {
        switch self {
        case .idle:
            return "Ready"
        case .capturing:
            return "Capturing displays…"
        case .recognizing:
            return "Reading Danish text…"
        case .translating:
            return "Translating on device…"
        case let .showing(regionCount):
            return "Hover learning active · \(regionCount) words"
        case let .failed(message):
            return message
        }
    }

    var isWorking: Bool {
        switch self {
        case .capturing, .recognizing, .translating:
            return true
        default:
            return false
        }
    }
}
