import CoreGraphics

public struct ScrollCaptureSourceGeometry: Equatable, Sendable {
    public var sourceRect: CGRect
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        sourceRect: CGRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.sourceRect = sourceRect
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public static func resolve(
        captureRect: CGRect,
        displayRect: CGRect,
        pointPixelScale: CGFloat
    ) -> Self? {
        guard captureRect.width > 0,
              captureRect.height > 0,
              displayRect.width > 0,
              displayRect.height > 0,
              pointPixelScale > 0,
              displayRect.contains(captureRect) else {
            return nil
        }

        let sourceRect = captureRect.offsetBy(
            dx: -displayRect.minX,
            dy: -displayRect.minY
        )
        return Self(
            sourceRect: sourceRect,
            pixelWidth: max(1, Int((sourceRect.width * pointPixelScale).rounded())),
            pixelHeight: max(1, Int((sourceRect.height * pointPixelScale).rounded()))
        )
    }
}
