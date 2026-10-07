import AppKit
import Foundation
import ScreenshotCore
import QuartzCore

struct RegionSelection {
    var rect: CGRect
    var image: CGImage
}

@MainActor
final class RegionSelectionController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<CGRect, Error>?
    private var activeCaptureRect: CGRect?
    private var selectionID: UUID?
    private var previousCursor: NSCursor?
    static let escapeSignature: UInt32 = 0x53484553 // SHES, separate from the capture hotkey
    private let escapeHotKey = GlobalHotKeyService(signature: escapeSignature, allowsUnmodifiedEscape: true)

    var selectionEscapeIdentifier: UInt32? { escapeHotKey.activeEventIdentifier }

    var hasPendingSelection: Bool { continuation != nil && panel != nil }
    var hasRenderedPendingSelection: Bool {
        (panel?.contentView as? SelectionOverlayView)?.hasDrawnFirstFrame == true
    }

    func selectRegion(using captureService: CaptureService) async throws -> RegionSelection {
        if continuation != nil { throw CaptureError.cancelled }
        if Task.isCancelled { throw CaptureError.cancelled }
        try ScreenCapturePermission.requireAccess(preflight: captureService.screenCaptureAccess)
        let screen = try screenUnderPointer()
        let rect = try await selectLiveRegion(captureRect: captureRect(for: screen))
        try Task.checkCancellation()
        // Capture only after the panel has closed. The content filter also excludes
        // this app, so WindowServer ordering cannot put the blue frame in the image.
        let image = try await captureService.captureSelectedRegion(rect: rect)
        return RegionSelection(rect: rect, image: image)
    }

    // Scrolling keeps its frozen first frame for menus and hover content.
    func selectFrozenRegion(using captureService: CaptureService) async throws -> RegionSelection {
        if continuation != nil || Task.isCancelled { throw CaptureError.cancelled }
        let screen = try screenUnderPointer()
        let preparationStarted = ContinuousClock.now
        CaptureTelemetry.logger.notice("selection_backdrop_preparation_started")
        let backdropImage = try await captureService.captureFrozenScreen(rect: captureRect(for: screen))
        let duration = preparationStarted.duration(to: .now)
        let milliseconds = Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        CaptureTelemetry.logger.notice("selection_backdrop_preparation_finished milliseconds=\(milliseconds, privacy: .public)")
        return try await selectRegion(on: screen, backdropImage: backdropImage)
    }

    private func screenUnderPointer() throws -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else { throw CaptureError.cancelled }
        return screen
    }

    func selectRegion(on screen: NSScreen, backdropImage: CGImage) async throws -> RegionSelection {
        try await selectRegion(captureRect: captureRect(for: screen), backdropImage: backdropImage)
    }

    func selectRegion(captureRect: CGRect, backdropImage: CGImage) async throws -> RegionSelection {
        let rect = try await selectRect(captureRect: captureRect, backdropImage: backdropImage)
        let localRect = rect.offsetBy(dx: -captureRect.minX, dy: -captureRect.minY)
        guard let image = cropFrozenScreen(localRect: localRect, screenSize: captureRect.size, image: backdropImage) else {
            throw CaptureError.missingOutput
        }
        return RegionSelection(rect: rect, image: image)
    }

    func selectLiveRegion(captureRect: CGRect) async throws -> CGRect {
        try await selectRect(captureRect: captureRect, backdropImage: nil)
    }

    private func selectRect(captureRect: CGRect, backdropImage: CGImage?) async throws -> CGRect {
        guard continuation == nil, selectionID == nil, !Task.isCancelled,
              let mainTop = NSScreen.screens.first?.frame.maxY else { throw CaptureError.cancelled }
        let frame = ScreenCoordinateTransform.appKitRect(fromCaptureRect: captureRect, mainScreenTop: mainTop)
        let id = UUID()
        selectionID = id
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                presentOverlay(frame: frame, captureRect: captureRect, backdropImage: backdropImage)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.selectionID == id else { return }
                self?.cancelActiveSelection()
            }
        }
    }

    @discardableResult
    func cancelActiveSelection() -> Bool {
        guard continuation != nil else { return false }
        finish(.failure(CaptureError.cancelled))
        return true
    }

    private func presentOverlay(frame: CGRect, captureRect: CGRect, backdropImage: CGImage?) {
        guard let id = selectionID else {
            finish(.failure(CaptureError.cancelled))
            return
        }
        previousCursor = NSCursor.current
        do {
            try escapeHotKey.register(HotKey(key: "ESC", keyCode: 53, modifiers: [])) { [weak self] in
                Task { @MainActor [weak self] in
                    guard self?.selectionID == id else { return }
                    self?.cancelActiveSelection()
                }
            }
        } catch {
            CaptureTelemetry.logger.error("selection_escape_registration_failed error=\(error.localizedDescription, privacy: .public)")
        }
        activeCaptureRect = captureRect
        let panel = KeyableSelectionPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.title = "Выбор области снимка"
        panel.setAccessibilityLabel("Выбор области снимка")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let overlay = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: frame.size),
            backdropImage: backdropImage
        )
        overlay.setAccessibilityLabel("Потяните, чтобы выбрать область снимка")
        overlay.onComplete = { [weak self] rect in
            guard let self, self.selectionID == id else { return }
            self.complete(localRect: rect)
        }
        let cancel = { [weak self] in
            guard let self, self.selectionID == id else { return }
            self.finish(.failure(CaptureError.cancelled))
        }
        overlay.onCancel = cancel
        panel.onCancel = cancel
        panel.contentView = overlay
        panel.delegate = self
        self.panel = panel
        panel.ignoresMouseEvents = true
        // Populate the backing store before ordering a transparent panel onscreen.
        panel.display()
        CATransaction.flush()
        panel.orderFrontRegardless()
        // Some AppKit configurations cannot draw a hidden window: finish painting
        // after ordering it, while mouse input is still disabled.
        if !overlay.hasDrawnFirstFrame { panel.display() }
        CATransaction.flush()
        guard overlay.hasDrawnFirstFrame else {
            CaptureTelemetry.logger.error("selection_overlay_initial_draw_failed")
            finish(.failure(CaptureError.missingOutput))
            return
        }
        panel.ignoresMouseEvents = false
        focusPendingOverlayIfNeeded()
        CaptureTelemetry.logger.notice("selection_overlay_presented live=\(backdropImage == nil) rendered=\(overlay.hasDrawnFirstFrame) active_space=\(panel.isOnActiveSpace) occluded=\(!panel.occlusionState.contains(.visible)) width=\(Int(frame.width), privacy: .public) height=\(Int(frame.height), privacy: .public)")
        let yieldedAt = ContinuousClock.now
        DispatchQueue.main.async { [weak self] in
            guard self?.selectionID == id else { return }
            let elapsed = yieldedAt.duration(to: .now)
            let milliseconds = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            CaptureTelemetry.logger.notice("selection_main_queue_resumed milliseconds=\(milliseconds, privacy: .public)")
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        CaptureTelemetry.logger.notice("selection_overlay_occlusion_changed visible=\(window.occlusionState.contains(.visible)) active_space=\(window.isOnActiveSpace)")
    }

    func focusPendingOverlayIfNeeded() {
        guard let panel,
              let overlay = panel.contentView as? SelectionOverlayView else { return }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(overlay)
        NSCursor.crosshair.set()
        CaptureTelemetry.logger.notice("selection_overlay_focused key=\(panel.isKeyWindow) visible=\(panel.isVisible)")
    }

    private func complete(localRect: CGRect) {
        guard localRect.width >= 3, localRect.height >= 3,
              let captureRect = activeCaptureRect else {
            finish(.failure(CaptureError.cancelled))
            return
        }
        let global = CGRect(
            x: captureRect.minX + localRect.minX,
            y: captureRect.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
        finish(.success(global))
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

    private func finish(_ result: Result<CGRect, Error>) {
        selectionID = nil
        escapeHotKey.unregister()
        panel?.orderOut(nil)
        panel = nil
        activeCaptureRect = nil
        previousCursor?.set()
        previousCursor = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

final class SelectionOverlayView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let backdropImage: NSImage?
    private var pendingDamage: [CGRect] = []
    private(set) var hasDrawnFirstFrame = false
    private(set) var lastPaintedArea: CGFloat = 0

    init(frame frameRect: NSRect, backdropImage: CGImage?) {
        self.backdropImage = backdropImage.map { NSImage(cgImage: $0, size: frameRect.size) }
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        let previous = visualDamageRects
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        NSCursor.crosshair.set()
        invalidate(previous + visualDamageRects)
    }

    override func mouseDragged(with event: NSEvent) {
        let previous = visualDamageRects
        currentPoint = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        invalidate(previous + visualDamageRects)
    }

    private func invalidate(_ rects: [CGRect]) {
        for rect in rects {
            let clipped = rect.intersection(bounds)
            guard !clipped.isEmpty else { continue }
            pendingDamage.append(clipped)
            setNeedsDisplay(clipped)
        }
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        onComplete?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        let firstDrawStarted = ContinuousClock.now
        let isFirstDraw = !hasDrawnFirstFrame
        defer {
            if isFirstDraw {
                hasDrawnFirstFrame = true
                let duration = firstDrawStarted.duration(to: .now)
                let milliseconds = Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
                CaptureTelemetry.logger.notice("selection_overlay_first_draw_finished milliseconds=\(milliseconds, privacy: .public)")
            }
        }
        // Keep separate edge rectangles: their bounding box can cover the whole
        // monitor, while the pixels that actually need painting are only strips.
        let damage = pendingDamage.isEmpty ? [dirtyRect] : pendingDamage.map { $0.intersection(dirtyRect) }.filter { !$0.isEmpty }
        pendingDamage.removeAll(keepingCapacity: true)
        lastPaintedArea = damage.reduce(0) { $0 + $1.width * $1.height }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext.current?.cgContext, !damage.isEmpty else { return }
        context.clip(to: damage)
        context.clear(dirtyRect)
        if let backdropImage {
            backdropImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                               respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        } else {
            NSColor.white.withAlphaComponent(1.0 / 255).setFill()
            NSBezierPath(rect: dirtyRect).fill()
        }
        guard !selectionRect.isEmpty else {
            hintText.draw(at: hintBounds.origin)
            return
        }
        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        outline.lineWidth = 2
        outline.stroke()
        sizeLabelText.draw(at: sizeLabelBounds.origin)
    }

    private var selectionRect: CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        return CGRect(x: min(startPoint.x, currentPoint.x), y: min(startPoint.y, currentPoint.y),
                      width: abs(currentPoint.x - startPoint.x), height: abs(currentPoint.y - startPoint.y)).intersection(bounds)
    }

    private var hintText: NSAttributedString {
        let text = "Потяните, чтобы выбрать область  •  Esc - отмена"
        return NSAttributedString(string: "  \(text)  ", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55),
        ])
    }

    private var hintBounds: CGRect {
        let size = hintText.size()
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private var visualDamageRects: [CGRect] {
        let rect = selectionRect
        guard !rect.isEmpty else { return [hintBounds.insetBy(dx: -2, dy: -2)] }
        let edge: CGFloat = 4
        return [
            CGRect(x: rect.minX - edge, y: rect.minY - edge, width: rect.width + 2 * edge, height: 2 * edge),
            CGRect(x: rect.minX - edge, y: rect.maxY - edge, width: rect.width + 2 * edge, height: 2 * edge),
            CGRect(x: rect.minX - edge, y: rect.minY - edge, width: 2 * edge, height: rect.height + 2 * edge),
            CGRect(x: rect.maxX - edge, y: rect.minY - edge, width: 2 * edge, height: rect.height + 2 * edge),
            sizeLabelBounds.insetBy(dx: -2, dy: -2),
        ]
    }

    private var sizeLabelBounds: CGRect {
        let size = sizeLabelText.size()
        let origin = SelectionSizeLabelPlacement.origin(near: currentPoint ?? selectionRect.origin,
                                                       labelSize: size, in: bounds)
        return CGRect(origin: origin, size: size)
    }

    private var sizeLabelText: NSAttributedString {
        let text = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        return NSAttributedString(string: "  \(text)  ", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.8),
        ])
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
