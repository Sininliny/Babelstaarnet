import CoreGraphics
import Foundation

enum ExplanationMode: String, CaseIterable, Identifiable, Sendable {
    case english
    case easyDanish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "English meaning"
        case .easyDanish:
            return "Easy Danish"
        }
    }

    var menuTitle: String {
        switch self {
        case .english:
            return "Danish → English"
        case .easyDanish:
            return "Danish · easy explanation"
        }
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
    let frame: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String = "",
        beginnerExplanation: String = "",
        frame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.beginnerExplanation = beginnerExplanation
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
    let explanationMode: ExplanationMode
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
