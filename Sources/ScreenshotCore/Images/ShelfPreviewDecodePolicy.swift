import Foundation

public struct ShelfPreviewDecodePlan: Equatable, Sendable {
    public var maximumPixelSize: Int
    public var estimatedDimensions: PixelDimensions

    public init(maximumPixelSize: Int, estimatedDimensions: PixelDimensions) {
        self.maximumPixelSize = maximumPixelSize
        self.estimatedDimensions = estimatedDimensions
    }

    public var estimatedPixelCount: Int {
        estimatedDimensions.width * estimatedDimensions.height
    }
}

public enum ShelfPreviewDecodePolicy {
    public static let maximumDecodedPixels = 16_777_216
    public static let maximumLongEdge = 32_768

    private static let resolutionSteps = [
        320, 640, 1_024, 1_536, 2_048, 3_072, 4_096, 6_144,
        8_192, 12_288, 16_384, 24_576, 32_768,
    ]

    public static func plan(
        image: PixelDimensions,
        viewport: CanvasSize,
        zoomScale: Double,
        backingScale: Double
    ) -> ShelfPreviewDecodePlan {
        let width = max(1, image.width)
        let height = max(1, image.height)
        let longestSourceEdge = max(width, height)
        let shortestSourceEdge = min(width, height)
        let aspectRatio = Double(longestSourceEdge) / Double(shortestSourceEdge)
        let areaLimitedLongEdge = Int(
            floor(sqrt(Double(maximumDecodedPixels) * aspectRatio))
        )
        let allowedLongEdge = max(
            1,
            min(longestSourceEdge, maximumLongEdge, areaLimitedLongEdge)
        )

        let fitted = EditorZoomPolicy.aspectFitSize(
            image: CanvasSize(width: Double(width), height: Double(height)),
            viewport: viewport
        )
        let displayedLongEdge = max(fitted.width, fitted.height) * max(zoomScale, 0.01)
        let desiredLongEdge = max(1, Int(ceil(displayedLongEdge * max(backingScale, 1))))
        let steppedLongEdge = resolutionSteps.first(where: { $0 >= desiredLongEdge })
            ?? maximumLongEdge
        let requestedLongEdge = min(allowedLongEdge, steppedLongEdge)
        let scale = min(1, Double(requestedLongEdge) / Double(longestSourceEdge))
        let estimated = PixelDimensions(
            width: max(1, Int(floor(Double(width) * scale))),
            height: max(1, Int(floor(Double(height) * scale)))
        )

        return ShelfPreviewDecodePlan(
            maximumPixelSize: requestedLongEdge,
            estimatedDimensions: estimated
        )
    }
}
