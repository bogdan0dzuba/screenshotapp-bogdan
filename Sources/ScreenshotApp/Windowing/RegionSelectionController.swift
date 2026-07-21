import AppKit
import Foundation
import ScreenshotCore

struct RegionSelection {
    var rect: CGRect
    var image: CGImage
}

@MainActor
final class RegionSelectionController {
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<RegionSelection, Error>?
    private var activeScreen: NSScreen?
    private var frozenScreen: CGImage?

    func selectRegion(using captureService: CaptureService) async throws -> RegionSelection {
        if continuation != nil { throw CaptureError.cancelled }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { throw CaptureError.cancelled }
        let backdropImage = try await captureService.captureFrozenScreen(rect: captureRect(for: screen))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentOverlay(on: screen, backdropImage: backdropImage)
        }
    }

    private func presentOverlay(on screen: NSScreen, backdropImage: CGImage) {
        activeScreen = screen
        frozenScreen = backdropImage
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let overlay = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            backdropImage: backdropImage
        )
        overlay.onComplete = { [weak self] rect in self?.complete(localRect: rect) }
        overlay.onCancel = { [weak self] in self?.finish(.failure(CaptureError.cancelled)) }
        panel.contentView = overlay
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(overlay)
        CaptureTelemetry.logger.info("selection_overlay_presented")
    }

    private func complete(localRect: CGRect) {
        guard localRect.width >= 3, localRect.height >= 3,
              let screen = activeScreen,
              let frozenScreen,
              let image = cropFrozenScreen(
                localRect: localRect,
                screenSize: screen.frame.size,
                image: frozenScreen
              ) else {
            finish(.failure(CaptureError.cancelled))
            return
        }
        let global = CGRect(
            x: screen.frame.minX + localRect.minX,
            y: captureRect(for: screen).minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
        finish(.success(RegionSelection(rect: global, image: image)))
    }

    private func captureRect(for screen: NSScreen) -> CGRect {
        let mainTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return CGRect(
            x: screen.frame.minX,
            y: mainTop - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private func cropFrozenScreen(localRect: CGRect, screenSize: CGSize, image: CGImage) -> CGImage? {
        let pixelRect = FrozenScreenCrop.pixelRect(
            selection: localRect,
            viewSize: screenSize,
            imagePixelSize: CGSize(width: image.width, height: image.height)
        )
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return image.cropping(to: pixelRect)
    }

    private func finish(_ result: Result<RegionSelection, Error>) {
        panel?.orderOut(nil)
        panel = nil
        activeScreen = nil
        frozenScreen = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

private final class SelectionOverlayView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let backdropImage: NSImage

    init(frame frameRect: NSRect, backdropImage: CGImage) {
        self.backdropImage = NSImage(cgImage: backdropImage, size: frameRect.size)
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        onComplete?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawBackdrop()
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()
        guard !selectionRect.isEmpty else {
            drawHint()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        drawBackdrop()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        outline.lineWidth = 2
        outline.stroke()
        drawSizeLabel()
    }

    private func drawBackdrop() {
        backdropImage.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private var selectionRect: CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ).intersection(bounds)
    }

    private func drawHint() {
        let text = "Потяните, чтобы выбрать область  •  Esc - отмена"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55),
        ]
        let value = NSAttributedString(string: "  \(text)  ", attributes: attributes)
        let size = value.size()
        value.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    private func drawSizeLabel() {
        let text = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.8),
        ]
        let value = NSAttributedString(string: "  \(text)  ", attributes: attributes)
        let y = selectionRect.maxY + 6 + value.size().height < bounds.maxY
            ? selectionRect.maxY + 6
            : max(6, selectionRect.minY - value.size().height - 6)
        value.draw(at: CGPoint(x: selectionRect.minX, y: y))
    }
}
