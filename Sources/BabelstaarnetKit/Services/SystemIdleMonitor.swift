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
    static let activePollInterval = Duration.milliseconds(220)
    static let suspendedPollInterval = Duration.seconds(1)

    /// How far the active poll may drift from its interval.
    ///
    /// A deadline the system may slide can be served alongside a wake-up it was
    /// going to make anyway, where an exact one forces a wake-up of its own —
    /// and on a laptop the wake-up, not the work, is most of what a poll this
    /// small costs. This one is scheduled while the reader is reading, so there
    /// is other work to be carried along by, and it is looking for a pointer
    /// that moves in tenths of a second rather than in milliseconds.
    ///
    /// The suspended poll deliberately has none. It is the only thing standing
    /// between a reader who has come back and detection resuming, and on the
    /// idle machine it runs on there would be nothing to coalesce with anyway:
    /// it would buy no power and spend the one latency that is felt.
    static let activePollTolerance = Duration.milliseconds(40)

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
