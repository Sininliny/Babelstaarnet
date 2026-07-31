import Foundation

@main
enum BeginnerDanishServiceChecks {
    static func main() {
        let service = BeginnerDanishService()

        precondition(
            service.localExplanation(for: "LÆRE,")?
                .localizedCaseInsensitiveContains("viden") == true
        )
        precondition(
            service.localExplanation(for: "eller")?
                .localizedCaseInsensitiveContains("valg") == true
        )
        precondition(service.localExplanation(for: "xyzzy") == nil)

        let cleaned = service.clean(
            explanation: "  En   kort forklaring  "
        )
        precondition(cleaned == "En kort forklaring.")

        let long = service.clean(
            explanation: String(repeating: "forklaring ", count: 40)
        )
        precondition(long.count <= 221)
        precondition(long.hasSuffix("…"))

        print("Easy Danish explanation checks passed")
    }
}
