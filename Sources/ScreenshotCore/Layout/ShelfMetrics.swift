import CoreGraphics

public enum ShelfMetrics {
    public static let expandedSize = CGSize(width: 380, height: 520)
    public static let minimumExpandedSize = CGSize(width: 320, height: 360)
    public static let collapsedSize = CGSize(width: 60, height: 34)
    public static let toggleHitTargetSize = CGSize(width: 28, height: 28)
    public static let collapsedHorizontalPadding: CGFloat = 4
    public static let collapsedContentSpacing: CGFloat = 3
    public static let collapsedCountWidth: CGFloat = 18
    public static let headerHeight: CGFloat = 32
    public static let quickActionHeight: CGFloat = 28
    public static let captureBarHeight: CGFloat = 30
    public static let expandedContentPadding: CGFloat = 8
    public static let historyMinimumHeight: CGFloat = 80
    public static let historyIdealHeight: CGFloat = 112
    public static let historyMaximumHeight: CGFloat = 144

    public static func collapsedCountFontSize(for count: Int) -> CGFloat {
        count > 9 ? 12 : 14
    }

    public static func constrainedExpandedSize(_ requestedSize: CGSize, visibleSize: CGSize) -> CGSize {
        let maximumWidth = max(1, visibleSize.width)
        let maximumHeight = max(1, visibleSize.height)
        let minimumWidth = min(minimumExpandedSize.width, maximumWidth)
        let minimumHeight = min(minimumExpandedSize.height, maximumHeight)
        return CGSize(
            width: min(max(requestedSize.width, minimumWidth), maximumWidth),
            height: min(max(requestedSize.height, minimumHeight), maximumHeight)
        )
    }
}
