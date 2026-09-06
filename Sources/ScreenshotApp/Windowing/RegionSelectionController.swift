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
    private var activeCaptureRect: CGRect?
    private var frozenScreen: CGImage?

    func selectRegion(using captureService: CaptureService) async throws -> RegionSelection {
        if continuation != nil { throw CaptureError.cancelled }
        if Task.isCancelled { throw CaptureError.cancelled }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { throw CaptureError.cancelled }
        let backdropImage = try await captureService.captureFrozenScreen(rect: captureRect(for: screen))
        return try await selectRegion(on: screen, backdropImage: backdropImage)
    }

    func selectRegion(on screen: NSScreen, backdropImage: CGImage) async throws -> RegionSelection {
        try await selectRegion(captureRect: captureRect(for: screen), backdropImage: backdropImage)
    }

    func selectRegion(captureRect: CGRect, backdropImage: CGImage) async throws -> RegionSelection {
        guard continuation == nil, !Task.isCancelled,
              let mainTop = NSScreen.screens.first?.frame.maxY else { throw CaptureError.cancelled }
        let frame = ScreenCoordinateTransform.appKitRect(fromCaptureRect: captureRect, mainScreenTop: mainTop)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentOverlay(frame: frame, captureRect: captureRect, backdropImage: backdropImage)
        }
    }

    @discardableResult
    func cancelActiveSelection() -> Bool {
        guard continuation != nil else { return false }
        finish(.failure(CaptureError.cancelled))
        return true
    }

    private func presentOverlay(frame: CGRect, captureRect: CGRect, backdropImage: CGImage) {
        activeCaptureRect = captureRect
        frozenScreen = backdropImage
        let panel = KeyableSelectionPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.title = "Выбор области снимка"
        panel.setAccessibilityLabel("Выбор области снимка")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let overlay = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: frame.size),
            backdropImage: backdropImage
        )
        overlay.setAccessibilityLabel("Потяните, чтобы выбрать область снимка")
        overlay.onComplete = { [weak self] rect in self?.complete(localRect: rect) }
        overlay.onCancel = { [weak self] in self?.finish(.failure(CaptureError.cancelled)) }
        panel.onCancel = { [weak self] in self?.finish(.failure(CaptureError.cancelled)) }
        panel.contentView = overlay
        self.panel = panel
        panel.orderFrontRegardless()
        NSApp.activate()
        focusPendingOverlayIfNeeded()
        CaptureTelemetry.logger.info("selection_overlay_presented")
    }

    func focusPendingOverlayIfNeeded() {
        guard let panel,
              let overlay = panel.contentView as? SelectionOverlayView else { return }
        panel.orderFrontRegardless()
        guard NSApp.isActive else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(overlay)
    }

    private func complete(localRect: CGRect) {
        guard localRect.width >= 3, localRect.height >= 3,
              let captureRect = activeCaptureRect,
              let frozenScreen,
              let image = cropFrozenScreen(
                localRect: localRect,
                screenSize: captureRect.size,
                image: frozenScreen
              ) else {
            finish(.failure(CaptureError.cancelled))
            return
        }
        let global = CGRect(
            x: captureRect.minX + localRect.minX,
            y: captureRect.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
        finish(.success(RegionSelection(rect: global, image: image)))
    }

    private func captureRect(for screen: NSScreen) -> CGRect {
        let mainTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return ScreenCoordinateTransform.captureRect(
            fromAppKitRect: screen.frame,
            mainScreenTop: mainTop
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
        activeCaptureRect = nil
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

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
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
        drawSizeLabel(near: currentPoint ?? selectionRect.origin)
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

    private func drawSizeLabel(near pointer: CGPoint) {
        let text = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.8),
        ]
        let value = NSAttributedString(string: "  \(text)  ", attributes: attributes)
        let origin = SelectionSizeLabelPlacement.origin(
            near: pointer,
            labelSize: value.size(),
            in: bounds
        )
        value.draw(at: origin)
    }
}

private final class KeyableSelectionPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}
