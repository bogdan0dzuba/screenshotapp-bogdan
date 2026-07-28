import CoreGraphics

private struct ScrollCaptureTrailIncrement: Equatable, Sendable {
    var direction: ScrollCaptureDirection
    var amount: CGFloat
}

public struct ScrollCaptureTrail: Equatable, Sendable {
    public private(set) var appendHeight: CGFloat = 0
    public private(set) var prependHeight: CGFloat = 0

    private var increments: [ScrollCaptureTrailIncrement] = []

    public init() {}

    public mutating func append(frameHeight: Int, overlap: Int, captureHeight: CGFloat) {
        add(.down, frameHeight: frameHeight, overlap: overlap, captureHeight: captureHeight)
    }

    public mutating func prepend(frameHeight: Int, overlap: Int, captureHeight: CGFloat) {
        add(.up, frameHeight: frameHeight, overlap: overlap, captureHeight: captureHeight)
    }

    public mutating func undoLast() {
        guard let increment = increments.popLast() else { return }
        let direction = increment.direction
        let amount = increment.amount
        switch direction {
        case .down: appendHeight = max(0, appendHeight - amount)
        case .up: prependHeight = max(0, prependHeight - amount)
        }
    }

    public mutating func reset() {
        appendHeight = 0
        prependHeight = 0
        increments.removeAll()
    }

    public func externalRect(
        captureRect: CGRect,
        screenRect: CGRect,
        direction: ScrollCaptureDirection
    ) -> CGRect {
        let rect: CGRect
        switch direction {
        case .down:
            rect = CGRect(
                x: captureRect.minX,
                y: captureRect.maxY,
                width: captureRect.width,
                height: appendHeight
            )
        case .up:
            rect = CGRect(
                x: captureRect.minX,
                y: captureRect.minY - prependHeight,
                width: captureRect.width,
                height: prependHeight
            )
        }
        return rect.intersection(screenRect)
    }

    private mutating func add(
        _ direction: ScrollCaptureDirection,
        frameHeight: Int,
        overlap: Int,
        captureHeight: CGFloat
    ) {
        guard frameHeight > 0, captureHeight > 0 else { return }
        let amount = max(0, CGFloat(frameHeight - overlap) / CGFloat(frameHeight)) * captureHeight
        guard amount > 0 else { return }
        increments.append(ScrollCaptureTrailIncrement(direction: direction, amount: amount))
        switch direction {
        case .down: appendHeight += amount
        case .up: prependHeight += amount
        }
    }
}
