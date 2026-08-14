import Foundation
@testable import BabelCore
@testable import BabelOCR
@testable import BabelTranslate
@testable import BabelLexicon
@testable import BabelSpeech
@testable import LanguageDanish
@testable import BabelstaarnetKit

@main
enum PowerSavingPolicyChecks {
    static func main() {
        precondition(
            !PowerSavingPolicy.shouldSuspend(
                enabled: true,
                learningModeActive: true,
                idleDuration: 4.99
            )
        )
        precondition(
            PowerSavingPolicy.shouldSuspend(
                enabled: true,
                learningModeActive: true,
                idleDuration: 5
            )
        )
        precondition(
            !PowerSavingPolicy.shouldSuspend(
                enabled: false,
                learningModeActive: true,
                idleDuration: 60
            )
        )
        precondition(
            !PowerSavingPolicy.shouldSuspend(
                enabled: true,
                learningModeActive: false,
                idleDuration: 60
            )
        )
        precondition(
            PowerSavingPolicy.stationaryRefreshInterval(idleDuration: 0.5)
                == 1.5
        )
        precondition(
            PowerSavingPolicy.stationaryRefreshInterval(idleDuration: 2)
                == 3.5
        )

        print("Idle power-saving policy checks passed")
    }
}
