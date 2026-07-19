import CoreGraphics

public enum ShelfToggleGesturePolicy {
    public static let dragThreshold: CGFloat = 4

    public static func shouldToggle(start: CGPoint, end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < dragThreshold
    }
}

public struct ShelfToggleGestureState {
    public let start: CGPoint
    public private(set) var didDrag = false

    public init(start: CGPoint) {
        self.start = start
    }

    public mutating func update(to location: CGPoint) {
        if !ShelfToggleGesturePolicy.shouldToggle(start: start, end: location) {
            didDrag = true
        }
    }

    public var shouldToggleOnRelease: Bool { !didDrag }
}
