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
    let wordBridgeText: String
    let wordBridgeEnglishTokenIndexes: [Int]
    let learningText: String
    let englishSupport: String?
    let englishIsExpanded: Bool
    let adaptiveEnglishTokenIndexes: [Int]
    let showsControlsInWordBridge: Bool
    let showsControlsInSentenceBridge: Bool
    let showsEnglishSupportInSentenceBridge: Bool
    let knowledgeLevel: Int
    let maximumKnowledgeLevel: Int
    let knowledgeStageTitle: String
    let knownShortcutLabel: String
    let dontKnowShortcutLabel: String
    let pinShortcutLabel: String

    init(
        word: WordRegion,
        wordBridgeText: String = "",
        wordBridgeEnglishTokenIndexes: [Int] = [],
        learningText: String,
        englishSupport: String? = nil,
        englishIsExpanded: Bool = false,
        adaptiveEnglishTokenIndexes: [Int] = [],
        showsControlsInWordBridge: Bool = false,
        showsControlsInSentenceBridge: Bool = false,
        showsEnglishSupportInSentenceBridge: Bool = false,
        knowledgeLevel: Int = 0,
        maximumKnowledgeLevel: Int = 5,
        knowledgeStageTitle: String = "New",
        knownShortcutLabel: String = "1",
        dontKnowShortcutLabel: String = "2",
        pinShortcutLabel: String = "3"
    ) {
        self.word = word
        self.wordBridgeText = wordBridgeText
        self.wordBridgeEnglishTokenIndexes = wordBridgeEnglishTokenIndexes
        self.learningText = learningText
        self.englishSupport = englishSupport
        self.englishIsExpanded = englishIsExpanded
        self.adaptiveEnglishTokenIndexes = adaptiveEnglishTokenIndexes
        self.showsControlsInWordBridge = showsControlsInWordBridge
        self.showsControlsInSentenceBridge = showsControlsInSentenceBridge
        self.showsEnglishSupportInSentenceBridge =
            showsEnglishSupportInSentenceBridge
        self.knowledgeLevel = knowledgeLevel
        self.maximumKnowledgeLevel = maximumKnowledgeLevel
        self.knowledgeStageTitle = knowledgeStageTitle
        self.knownShortcutLabel = knownShortcutLabel
        self.dontKnowShortcutLabel = dontKnowShortcutLabel
        self.pinShortcutLabel = pinShortcutLabel
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
