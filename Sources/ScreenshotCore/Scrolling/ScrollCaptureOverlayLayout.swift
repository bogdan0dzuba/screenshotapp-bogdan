import CoreGraphics

public enum ScrollCaptureOverlayPresentation: Equatable, Sendable {
    case selectionReady
    case captured
    case pending(ScrollCaptureCoverage)
    case needsOverlap
}

public struct ScrollCaptureOverlayLayout: Equatable, Sendable {
    public var markedRect: CGRect?
    public var boundaryY: CGFloat?

    public init(
        markedRect: CGRect?,
        boundaryY: CGFloat?
    ) {
        self.markedRect = markedRect
        self.boundaryY = boundaryY
    }

    public static func layout(
        in bounds: CGRect,
        presentation: ScrollCaptureOverlayPresentation
    ) -> Self {
        guard bounds.width > 0, bounds.height > 0 else {
            return Self(markedRect: nil, boundaryY: nil)
        }

        switch presentation {
        case .selectionReady:
            return Self(markedRect: nil, boundaryY: nil)
        case .captured, .needsOverlap:
            return Self(markedRect: bounds, boundaryY: nil)
        case let .pending(coverage):
            let capturedHeight = bounds.height * coverage.alreadyCapturedFraction
            guard capturedHeight > 0 else {
                return Self(markedRect: nil, boundaryY: nil)
            }
            guard capturedHeight < bounds.height else {
                return Self(markedRect: bounds, boundaryY: nil)
            }
            switch coverage.alreadyCapturedEdge {
            case .top:
                let boundaryY = bounds.maxY - capturedHeight
                return Self(
                    markedRect: CGRect(
                        x: bounds.minX,
                        y: boundaryY,
                        width: bounds.width,
                        height: capturedHeight
                    ),
                    boundaryY: boundaryY
                )
            case .bottom:
                let boundaryY = bounds.minY + capturedHeight
                return Self(
                    markedRect: CGRect(
                        x: bounds.minX,
                        y: bounds.minY,
                        width: bounds.width,
                        height: capturedHeight
                    ),
                    boundaryY: boundaryY
                )
            }
        }
    }
}
