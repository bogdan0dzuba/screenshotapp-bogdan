public enum EditorCanvasLayout {
    public static func contentSize(
        image: CanvasSize,
        availableWidth: Double,
        horizontalPadding: Double
    ) -> CanvasSize {
        guard image.width > 0, image.height > 0 else {
            return CanvasSize(width: 0, height: 0)
        }
        let maximumWidth = max(1, availableWidth - horizontalPadding * 2)
        let scale = min(1, maximumWidth / image.width)
        return CanvasSize(width: image.width * scale, height: image.height * scale)
    }
}
