import Foundation

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

        print("Idle power-saving policy checks passed")
    }
}
