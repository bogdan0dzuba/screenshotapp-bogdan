import CoreGraphics

public enum ShelfSplitLayout {
    public static let minimumHistoryFraction = 0.2
    public static let maximumHistoryFraction = 0.65
    public static let defaultHistoryFraction = 0.3
    public static let dividerHeight: CGFloat = 10
    public static let latestMinimumHeight: CGFloat = 140
    public static let historyMinimumHeight: CGFloat = 80

    public static func historyFraction(
        _ value: Double,
        minimum: Double = minimumHistoryFraction,
        maximum: Double = maximumHistoryFraction
    ) -> Double {
        guard value.isFinite else { return defaultHistoryFraction }
        return min(max(value, minimum), maximum)
    }

    public static func historyFraction(
        startingFraction: Double,
        verticalTranslation: CGFloat,
        availableHeight: CGFloat
    ) -> Double {
        let height = max(1, availableHeight)
        let translated = startingFraction - Double(verticalTranslation / height)
        return historyFraction(translated)
    }

    public static func heights(
        availableHeight: CGFloat,
        historyFraction: Double,
        dividerHeight: CGFloat = dividerHeight,
        latestMinimumHeight: CGFloat = latestMinimumHeight,
        historyMinimumHeight: CGFloat = historyMinimumHeight
    ) -> (latest: CGFloat, history: CGFloat) {
        let contentHeight = max(0, availableHeight - dividerHeight)
        let totalMinimum = latestMinimumHeight + historyMinimumHeight

        guard contentHeight > 0 else { return (0, 0) }
        guard contentHeight >= totalMinimum else {
            let historyShare = totalMinimum > 0 ? historyMinimumHeight / totalMinimum : 0
            let history = contentHeight * historyShare
            return (contentHeight - history, history)
        }

        let requestedHistory = contentHeight * CGFloat(Self.historyFraction(historyFraction))
        let history = min(
            max(requestedHistory, historyMinimumHeight),
            contentHeight - latestMinimumHeight
        )
        return (contentHeight - history, history)
    }
}
