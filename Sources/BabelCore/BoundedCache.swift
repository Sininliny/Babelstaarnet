import Foundation

/// A small least-recently-used cache that prevents long reading sessions from
/// retaining every word ever seen. Trimming in batches keeps insertions cheap.
public final class BoundedCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var lastAccess: UInt64
    }

    private let capacity: Int
    private let trimTarget: Int
    private var entries: [Key: Entry] = [:]
    private var accessClock: UInt64 = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        trimTarget = max(Int(Double(capacity) * 0.9), 1)
        entries.reserveCapacity(capacity)
    }

    public var count: Int {
        entries.count
    }

    public subscript(key: Key) -> Value? {
        get {
            guard var entry = entries[key] else {
                return nil
            }
            entry.lastAccess = nextAccess()
            entries[key] = entry
            return entry.value
        }
        set {
            guard let newValue else {
                entries.removeValue(forKey: key)
                return
            }
            entries[key] = Entry(
                value: newValue,
                lastAccess: nextAccess()
            )
            trimIfNeeded()
        }
    }

    public func removeAll(keepingCapacity: Bool = true) {
        entries.removeAll(keepingCapacity: keepingCapacity)
    }

    private func nextAccess() -> UInt64 {
        accessClock &+= 1
        return accessClock
    }

    private func trimIfNeeded() {
        guard entries.count > capacity else {
            return
        }
        let removalCount = entries.count - trimTarget
        let oldestKeys = entries
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
            .prefix(removalCount)
            .map(\.key)
        for key in oldestKeys {
            entries.removeValue(forKey: key)
        }
    }
}
