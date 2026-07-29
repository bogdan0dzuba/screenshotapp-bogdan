import AppKit

public final class ScrollCaptureCoverageView: NSView {
    private var presentation = ScrollCaptureOverlayPresentation.selectionReady
    private var captureBounds: CGRect?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present(coverage: ScrollCaptureCoverage) {
        presentation = .pending(coverage)
        needsDisplay = true
    }

    /// За пределами рамки не рисуется ничего: прогресс показывает панель-рельс,
    /// а страница, которую пользователь читает и прокручивает, остаётся открытой.
    public func configure(captureRect: CGRect, screenRect: CGRect) {
        captureBounds = captureRect.offsetBy(dx: -screenRect.minX, dy: -screenRect.minY)
        needsDisplay = true
    }

    public func presentSelectionReady() {
        presentation = .selectionReady
        needsDisplay = true
    }

    public func presentCapturedViewport() {
        presentation = .captured
        needsDisplay = true
    }

    public func presentNeedsOverlap() {
        presentation = .needsOverlap
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let drawingBounds = captureBounds ?? bounds
        let layout = ScrollCaptureOverlayLayout.layout(
            in: drawingBounds,
            presentation: presentation
        )

        if let markedRect = layout.markedRect {
            NSColor.systemCyan.withAlphaComponent(0.30).setFill()
            markedRect.fill()
            NSColor.systemCyan.withAlphaComponent(0.86).setStroke()
            let markedOutline = NSBezierPath(rect: markedRect.insetBy(dx: 1, dy: 1))
            markedOutline.lineWidth = 2
            markedOutline.stroke()
        }

        if let boundaryY = layout.boundaryY {
            NSColor.systemGreen.withAlphaComponent(0.95).setStroke()
            let boundary = NSBezierPath()
            boundary.lineWidth = 3
            boundary.move(to: CGPoint(x: drawingBounds.minX, y: boundaryY))
            boundary.line(to: CGPoint(x: drawingBounds.maxX, y: boundaryY))
            boundary.stroke()
        }
    }
}
