import Foundation

/// Tracks image changes independently so a new capture does not invalidate old previews.
public struct HistoryImageRevisionIndex: Equatable, Sendable {
    private var values: [UUID: Int] = [:]

    public init() {}

    public func revision(for id: UUID) -> Int {
        values[id] ?? 0
    }

    public mutating func register(_ id: UUID) {
        if values[id] == nil {
            values[id] = 0
        }
    }

    public mutating func bump(_ id: UUID) {
        values[id, default: 0] &+= 1
    }

    public mutating func remove(_ id: UUID) {
        values.removeValue(forKey: id)
    }

    public mutating func removeAll() {
        values.removeAll(keepingCapacity: false)
    }

    public mutating func retain(ids: Set<UUID>) {
        values = values.filter { ids.contains($0.key) }
    }
}
