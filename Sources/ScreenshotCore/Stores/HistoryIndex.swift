import Foundation

public enum HistoryIndex {
    public static func pruned(
        items: [CaptureItem],
        automaticCleanupEnabled: Bool = true,
        maximumCount: Int,
        maximumAgeDays: Int,
        now: Date
    ) -> [CaptureItem] {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        guard automaticCleanupEnabled else { return sorted }
        guard maximumCount > 0, maximumAgeDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-TimeInterval(maximumAgeDays) * 86_400)
        return sorted
            .filter { $0.createdAt >= cutoff }
            .prefix(maximumCount)
            .map { $0 }
    }
}
