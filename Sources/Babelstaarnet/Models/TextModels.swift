import CoreGraphics
import Foundation

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
    var wordBridgeDanishText: String
    var wordBridgeTranslations: [String: String]
    var wordBridgeText: String
    var wordBridgeEnglishTokenIndexes: [Int]
    let frame: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String = "",
        wordBridgeDanishText: String = "",
        wordBridgeTranslations: [String: String] = [:],
        wordBridgeText: String = "",
        wordBridgeEnglishTokenIndexes: [Int] = [],
        frame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.wordBridgeDanishText = wordBridgeDanishText
        self.wordBridgeTranslations = wordBridgeTranslations
        self.wordBridgeText = wordBridgeText
        self.wordBridgeEnglishTokenIndexes = wordBridgeEnglishTokenIndexes
        self.frame = frame
        self.screenFrame = screenFrame
        self.displayID = displayID
    }
}

struct TextRegion: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceText: String
    let frame: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
    var words: [WordRegion]

    init(
        id: UUID = UUID(),
        sourceText: String,
        frame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID,
        words: [WordRegion]
    ) {
        self.id = id
        self.sourceText = sourceText
        self.frame = frame
        self.screenFrame = screenFrame
        self.displayID = displayID
        self.words = words
    }
}

struct HoverCard: Equatable, Sendable {
    let word: WordRegion
    let wordKnowledgeLevel: Int
    let wordEnglishMeaning: String?
    let wordBridgeText: String
    let wordBridgeEnglishTokenIndexes: [Int]
    let wordBridgeKnowledgeLevels: [Int: Int]
    let learningText: String
    let englishSupport: String?
    let englishIsExpanded: Bool
    let adaptiveEnglishTokenIndexes: [Int]
    let sentenceBridgeKnowledgeLevels: [Int: Int]
    let sentenceFocusTokenIndexes: [Int]
    /// Whether the sentence panel is the only panel on screen, because the
    /// reader switched the word panel off. It decides what the sentence panel
    /// has to carry on its own — the focused meaning, the English support, and
    /// the confirmation that a shortcut did something — rather than naming any
    /// one of them.
    let sentencePanelStandsAlone: Bool
    let showsAllEnglish: Bool
    let speaksOnHover: Bool
    let knownShortcutLabel: String
    let dontKnowShortcutLabel: String
    let pinShortcutLabel: String
    let showAllEnglishShortcutLabel: String

    init(
        word: WordRegion,
        wordKnowledgeLevel: Int = 0,
        wordEnglishMeaning: String? = nil,
        wordBridgeText: String = "",
        wordBridgeEnglishTokenIndexes: [Int] = [],
        wordBridgeKnowledgeLevels: [Int: Int] = [:],
        learningText: String,
        englishSupport: String? = nil,
        englishIsExpanded: Bool = false,
        adaptiveEnglishTokenIndexes: [Int] = [],
        sentenceBridgeKnowledgeLevels: [Int: Int] = [:],
        sentenceFocusTokenIndexes: [Int] = [],
        sentencePanelStandsAlone: Bool = false,
        showsAllEnglish: Bool = false,
        speaksOnHover: Bool = false,
        knownShortcutLabel: String = "1",
        dontKnowShortcutLabel: String = "2",
        pinShortcutLabel: String = "3",
        showAllEnglishShortcutLabel: String = "4"
    ) {
        self.word = word
        self.wordKnowledgeLevel = wordKnowledgeLevel
        self.wordEnglishMeaning = wordEnglishMeaning
        self.wordBridgeText = wordBridgeText
        self.wordBridgeEnglishTokenIndexes = wordBridgeEnglishTokenIndexes
        self.wordBridgeKnowledgeLevels = wordBridgeKnowledgeLevels
        self.learningText = learningText
        self.englishSupport = englishSupport
        self.englishIsExpanded = englishIsExpanded
        self.adaptiveEnglishTokenIndexes = adaptiveEnglishTokenIndexes
        self.sentenceBridgeKnowledgeLevels =
            sentenceBridgeKnowledgeLevels
        self.sentenceFocusTokenIndexes = sentenceFocusTokenIndexes
        self.sentencePanelStandsAlone =
            sentencePanelStandsAlone
        self.showsAllEnglish = showsAllEnglish
        self.speaksOnHover = speaksOnHover
        self.knownShortcutLabel = knownShortcutLabel
        self.dontKnowShortcutLabel = dontKnowShortcutLabel
        self.pinShortcutLabel = pinShortcutLabel
        self.showAllEnglishShortcutLabel = showAllEnglishShortcutLabel
    }
}

struct LearningBridgeConfiguration: Codable, Equatable, Sendable {
    var showsWordBridge: Bool
    var showsSentenceBridge: Bool

    static let both = Self(
        showsWordBridge: true,
        showsSentenceBridge: true
    )

    var hasVisibleBridge: Bool {
        showsWordBridge || showsSentenceBridge
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
            return "Capturing displays"
        case .recognizing:
            return "Reading Danish text"
        case .translating:
            return "Translating on device"
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
