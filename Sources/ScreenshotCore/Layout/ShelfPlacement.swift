import CoreGraphics

public enum ShelfPlacement {
    public static func resizedFrame(
        currentFrame: CGRect,
        targetSize: CGSize,
        visibleFrame: CGRect,
        hasBeenPresented: Bool,
        initialInset: CGFloat = 18
    ) -> CGRect {
        let boundedSize = CGSize(
            width: min(max(1, targetSize.width), visibleFrame.width),
            height: min(max(1, targetSize.height), visibleFrame.height)
        )
        if hasBeenPresented {
            return CGRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - boundedSize.height,
                width: boundedSize.width,
                height: boundedSize.height
            )
        }

        var origin = CGPoint(
            x: visibleFrame.maxX - boundedSize.width - initialInset,
            y: visibleFrame.minY + initialInset
        )

        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - boundedSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - boundedSize.height)
        origin.x = min(max(origin.x, visibleFrame.minX), maximumX)
        origin.y = min(max(origin.y, visibleFrame.minY), maximumY)

        return CGRect(origin: origin, size: boundedSize)
    }
}
