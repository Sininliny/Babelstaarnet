import CoreGraphics
import Foundation

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
    static let activePollInterval = Duration.milliseconds(140)
    static let suspendedPollInterval = Duration.milliseconds(500)

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
}
