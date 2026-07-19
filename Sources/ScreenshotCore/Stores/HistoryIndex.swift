import Foundation

public enum HistoryIndex {
    public static func pruned(
        items: [CaptureItem],
        maximumCount: Int,
        maximumAgeDays: Int,
        now: Date
    ) -> [CaptureItem] {
        guard maximumCount > 0, maximumAgeDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-TimeInterval(maximumAgeDays) * 86_400)
        return items
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(maximumCount)
            .map { $0 }
    }
}
