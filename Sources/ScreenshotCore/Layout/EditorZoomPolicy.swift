public enum EditorZoomPolicy {
    public static let minimumScale = 0.25
    public static let maximumScale = 8.0

    public static func scale(
        startScale: Double,
        magnification: Double,
        maximumScale customMaximumScale: Double = EditorZoomPolicy.maximumScale
    ) -> Double {
        min(customMaximumScale, max(minimumScale, startScale * magnification))
    }

    public static func contentSize(
        base: CanvasSize,
        scale: Double,
        maximumScale customMaximumScale: Double = EditorZoomPolicy.maximumScale
    ) -> CanvasSize {
        let clampedScale = min(customMaximumScale, max(minimumScale, scale))
        return CanvasSize(
            width: base.width * clampedScale,
            height: base.height * clampedScale
        )
    }

    public static func aspectFitSize(image: CanvasSize, viewport: CanvasSize) -> CanvasSize {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else {
            return CanvasSize(width: 0, height: 0)
        }
        let scale = min(viewport.width / image.width, viewport.height / image.height)
        return CanvasSize(width: image.width * scale, height: image.height * scale)
    }

    public static func maximumShelfScale(fittedSize: CanvasSize, viewport: CanvasSize) -> Double {
        guard fittedSize.width > 0, fittedSize.height > 0 else { return maximumScale }
        let widthFillScale = viewport.width / fittedSize.width
        let heightFillScale = viewport.height / fittedSize.height
        return min(64, max(maximumScale, widthFillScale, heightFillScale))
    }
}
