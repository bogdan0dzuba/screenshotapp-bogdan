import CoreGraphics

public enum ScreenshotDragGesturePolicy {
    public static let dragThreshold: CGFloat = 4

    public static func shouldBeginDrag(start: CGPoint, end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= dragThreshold
    }
}

public struct ScreenshotDragGestureState {
    public let start: CGPoint
    public private(set) var didDrag = false

    public init(start: CGPoint) {
        self.start = start
    }

    public mutating func update(to location: CGPoint) {
        if ScreenshotDragGesturePolicy.shouldBeginDrag(start: start, end: location) {
            didDrag = true
        }
    }

    public var shouldClickOnRelease: Bool { !didDrag }
}
