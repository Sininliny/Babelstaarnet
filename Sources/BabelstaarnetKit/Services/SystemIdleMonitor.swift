import CoreGraphics
import Foundation
import BabelCore
import BabelLexicon
import BabelOCR
import BabelSpeech
import BabelTranslate
import LanguageDanish

struct SystemIdleMonitor {
    func idleDuration() -> TimeInterval {
        let anyInputEvent = CGEventType(rawValue: UInt32.max)!
        let duration = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEvent
        )
        guard duration.isFinite else {
            return 0
        }
        return max(duration, 0)
    }
}

enum PowerSavingPolicy {
    static let defaultIdleThreshold: TimeInterval = 5
    static let activePollInterval = Duration.milliseconds(220)
    static let suspendedPollInterval = Duration.seconds(1)

    static func shouldSuspend(
        enabled: Bool,
        learningModeActive: Bool,
        idleDuration: TimeInterval,
        threshold: TimeInterval = defaultIdleThreshold
    ) -> Bool {
        enabled
            && learningModeActive
            && idleDuration >= threshold
    }

    static func stationaryRefreshInterval(
        idleDuration: TimeInterval
    ) -> TimeInterval {
        idleDuration < 1.5 ? 1.5 : 3.5
    }
}
