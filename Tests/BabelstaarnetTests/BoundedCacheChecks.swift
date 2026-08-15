import Foundation
@testable import BabelCore

@main
enum BoundedCacheChecks {
    static func main() {
        let cache = BoundedCache<String, String>(capacity: 3)
        cache["a"] = "alpha"
        cache["b"] = "beta"
        cache["c"] = "gamma"
        precondition(cache["a"] == "alpha")

        cache["d"] = "delta"
        precondition(cache.count <= 3)
        precondition(cache["a"] == "alpha")
        precondition(cache["d"] == "delta")
        precondition(cache["b"] == nil)
        precondition(cache["c"] == nil)

        for index in 0..<10_000 {
            cache["word-\(index)"] = "meaning-\(index)"
        }
        precondition(cache.count <= 3)
        precondition(cache["word-9999"] == "meaning-9999")

        print("Bounded runtime cache checks passed")
    }
}
