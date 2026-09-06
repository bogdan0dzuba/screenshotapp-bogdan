import CoreGraphics

private struct ScrollCaptureTrailIncrement: Equatable, Sendable {
    var direction: ScrollCaptureDirection
    var amount: CGFloat
}

/// Внешняя цветовая отметка уже принятых новых строк.
/// Это только AppKit-отрисовка, она не содержит копии страницы и не попадает в PNG.
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
        switch increment.direction {
        case .down:
            appendHeight = max(0, appendHeight - increment.amount)
        case .up:
            prependHeight = max(0, prependHeight - increment.amount)
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

    public func externalRects(captureRect: CGRect, screenRect: CGRect) -> [CGRect] {
        [
            externalRect(captureRect: captureRect, screenRect: screenRect, direction: .down),
            externalRect(captureRect: captureRect, screenRect: screenRect, direction: .up),
        ].filter { !$0.isNull && !$0.isEmpty }
    }

    private mutating func add(
        _ direction: ScrollCaptureDirection,
        frameHeight: Int,
        overlap: Int,
        captureHeight: CGFloat
    ) {
        guard frameHeight > 0, captureHeight > 0 else { return }
        let newContentFraction = max(0, CGFloat(frameHeight - overlap) / CGFloat(frameHeight))
        let amount = newContentFraction * captureHeight
        guard amount > 0 else { return }
        increments.append(ScrollCaptureTrailIncrement(direction: direction, amount: amount))
        switch direction {
        case .down: appendHeight += amount
        case .up: prependHeight += amount
        }
    }
}
