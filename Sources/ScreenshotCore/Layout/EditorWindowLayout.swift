public enum EditorWindowLayout {
    public static let minimumContentSize = CanvasSize(width: 440, height: 320)
    public static let chromeSize = CanvasSize(width: 136, height: 176)

    public static func contentSize(
        image: CanvasSize,
        visibleSize: CanvasSize,
        maximumScreenFraction: Double = 0.9
    ) -> CanvasSize {
        let maximum = CanvasSize(
            width: max(1, visibleSize.width * maximumScreenFraction),
            height: max(1, visibleSize.height * maximumScreenFraction)
        )
        guard image.width > 0, image.height > 0 else {
            return CanvasSize(
                width: min(minimumContentSize.width, maximum.width),
                height: min(minimumContentSize.height, maximum.height)
            )
        }

        let availableImageWidth = max(1, maximum.width - chromeSize.width)
        let availableImageHeight = max(1, maximum.height - chromeSize.height)
        let scale = min(
            1,
            min(availableImageWidth / image.width, availableImageHeight / image.height)
        )
        let desired = CanvasSize(
            width: image.width * scale + chromeSize.width,
            height: image.height * scale + chromeSize.height
        )
        return CanvasSize(
            width: min(maximum.width, max(minimumContentSize.width, desired.width)),
            height: min(maximum.height, max(minimumContentSize.height, desired.height))
        )
    }
}
