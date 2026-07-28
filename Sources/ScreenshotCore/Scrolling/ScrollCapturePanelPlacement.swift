import CoreGraphics

public enum ScrollCapturePanelPlacement {
    public static func frame(
        near captureRect: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 12,
        margin: CGFloat = 12
    ) -> CGRect {
        let minimumX = visibleFrame.minX + margin
        let maximumX = max(minimumX, visibleFrame.maxX - panelSize.width - margin)
        let x = min(
            max(captureRect.midX - panelSize.width / 2, minimumX),
            maximumX
        )

        let aboveY = captureRect.maxY + gap
        let belowY = captureRect.minY - panelSize.height - gap
        let minimumY = visibleFrame.minY + margin
        let maximumY = max(minimumY, visibleFrame.maxY - panelSize.height - margin)
        let y: CGFloat
        if aboveY <= maximumY {
            y = aboveY
        } else if belowY >= minimumY {
            y = belowY
        } else {
            y = min(
                max(captureRect.maxY - panelSize.height - gap, minimumY),
                maximumY
            )
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }
}
