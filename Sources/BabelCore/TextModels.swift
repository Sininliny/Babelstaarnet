import CoreGraphics
import Foundation

public struct CapturedDisplay: @unchecked Sendable {
    public let displayID: CGDirectDisplayID
    public let image: CGImage
    public let frame: CGRect
    public let screenFrame: CGRect

    public init(
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

public struct WordRegion: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceText: String
    public var translatedText: String
    public var wordBridgeDanishText: String
    public var wordBridgeTranslations: [String: String]
    public var wordBridgeText: String
    public var wordBridgeEnglishTokenIndexes: [Int]
    public let frame: CGRect
    public let screenFrame: CGRect
    public let displayID: CGDirectDisplayID

    public init(
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

public struct TextRegion: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceText: String
    public let frame: CGRect
    public let screenFrame: CGRect
    public let displayID: CGDirectDisplayID
    public var words: [WordRegion]

    public init(
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

public struct HoverCard: Equatable, Sendable {
    public let word: WordRegion
    public let wordKnowledgeLevel: Int
    public let wordEnglishMeaning: String?
    public let wordBridgeText: String
    public let wordBridgeEnglishTokenIndexes: [Int]
    public let wordBridgeKnowledgeLevels: [Int: Int]
    public let learningText: String
    public let englishSupport: String?
    public let englishIsExpanded: Bool
    public let adaptiveEnglishTokenIndexes: [Int]
    public let sentenceBridgeKnowledgeLevels: [Int: Int]
    public let sentenceFocusTokenIndexes: [Int]
    /// Whether the sentence panel is the only panel on screen, because the
    /// reader switched the word panel off. It decides what the sentence panel
    /// has to carry on its own — the focused meaning, the English support, and
    /// the confirmation that a shortcut did something — rather than naming any
    /// one of them.
    public let sentencePanelStandsAlone: Bool
    public let speaksOnHover: Bool
    public let knownShortcutLabel: String
    public let dontKnowShortcutLabel: String
    public let pinShortcutLabel: String

    /// Whether the profile counts this word as learned, which is what decides
    /// that the panel has no English to offer for it.
    public var wordIsKnown: Bool {
        wordKnowledgeLevel >= 4
    }

    public init(
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
        speaksOnHover: Bool = false,
        knownShortcutLabel: String = "1",
        dontKnowShortcutLabel: String = "2",
        pinShortcutLabel: String = "3"
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
        self.speaksOnHover = speaksOnHover
        self.knownShortcutLabel = knownShortcutLabel
        self.dontKnowShortcutLabel = dontKnowShortcutLabel
        self.pinShortcutLabel = pinShortcutLabel
    }
}

public struct LearningBridgeConfiguration: Codable, Equatable, Sendable {
    public var showsWordBridge: Bool
    public var showsSentenceBridge: Bool

    public static let both = Self(
        showsWordBridge: true,
        showsSentenceBridge: true
    )

    public var hasVisibleBridge: Bool {
        showsWordBridge || showsSentenceBridge
    }
}

public enum ScanPhase: Equatable {
    case idle
    case capturing
    case recognizing
    case translating
    case showing(regionCount: Int)
    case failed(message: String)

    public var label: String {
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

    public var isWorking: Bool {
        switch self {
        case .capturing, .recognizing, .translating:
            return true
        default:
            return false
        }
    }
}
