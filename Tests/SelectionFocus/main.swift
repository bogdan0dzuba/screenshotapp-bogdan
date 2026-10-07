import AppKit
import Carbon
import QuartzCore
import ScreenshotCore

@main
struct SelectionFocusChecks {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let controller = RegionSelectionController()
        do {
            _ = try await controller.selectRegion(using: CaptureService(screenCaptureAccess: { false }))
            throw NSError(domain: "live selector must respect screen-capture permission", code: 1)
        } catch ScreenCapturePermissionError.denied { }
        try require(!controller.hasPendingSelection, "denied access must not open the live selector")
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = context.makeImage()!
        let first = Task { @MainActor in
            try await controller.selectRegion(captureRect: CGRect(x: 0, y: 0, width: 32, height: 32), backdropImage: image)
        }
        try await waitForSelection(controller)
        let panel = NSApp.windows.first { $0.title == "Выбор области снимка" }!
        try require(panel.styleMask.contains(.nonactivatingPanel), "selection must not depend on app activation")
        try require(!panel.hidesOnDeactivate, "selection must remain visible when another app is active")
        try require(panel.isVisible && panel.isKeyWindow, "AppKit must mark the first panel visible and key")
        try require(controller.hasRenderedPendingSelection,
                    "initial draw must actually run before waiting for selection")
        let frozenPoint = CGPoint(x: panel.frame.minX + 4, y: panel.frame.minY + 4)
        try await waitForMouseRouting(panel, at: frozenPoint)
        panel.orderOut(nil)
        controller.focusPendingOverlayIfNeeded()
        try require(panel.isVisible && panel.isKeyWindow, "recovery must reveal and focus existing selection")
        try require(controller.hasPendingSelection, "refocusing must preserve live selection")
        let view = panel.contentView!
        try require(view.acceptsFirstMouse(for: nil), "inactive selection must accept the first mouse press")
        // A standalone test process may already have been activated by LaunchServices.
        // Establish the inactive state explicitly before exercising the first drag.
        NSApp.deactivate()
        let deactivationDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while NSApp.isActive {
            try require(ContinuousClock.now < deactivationDeadline, "test could not establish an inactive application")
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(panel.isVisible, "selection must survive application deactivation")
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
                               timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        panel.sendEvent(mouse(.leftMouseDown, 2, 2))
        panel.sendEvent(mouse(.leftMouseDragged, 20, 20))
        panel.sendEvent(mouse(.leftMouseUp, 20, 20))
        let selection = try await first.value
        try require(selection.rect.width == 18 && selection.rect.height == 18,
                    "NSWindow dispatch must complete the selected rectangle while the app is inactive")
        try require(!controller.hasPendingSelection, "successful selection must finish its session")
        let cancelled = Task { @MainActor in
            try await controller.selectRegion(captureRect: CGRect(x: 0, y: 0, width: 32, height: 32), backdropImage: image)
        }
        try await waitForSelection(controller)
        // Queue cancellation of the old task, then replace its completed selection before
        // its asynchronous cancellation handler reaches MainActor.
        cancelled.cancel()
        controller.cancelActiveSelection()
        do { _ = try await cancelled.value; throw NSError(domain: "cancel did not finish", code: 1) }
        catch CaptureError.cancelled { }
        catch is CancellationError { }
        let second = Task { @MainActor in
            try await controller.selectRegion(captureRect: CGRect(x: 0, y: 0, width: 32, height: 32), backdropImage: image)
        }
        try await waitForSelection(controller)
        for _ in 0..<10 { await Task.yield() }
        try require(controller.hasPendingSelection, "old cancellation must not close new selection")
        controller.cancelActiveSelection()
        do { _ = try await second.value; throw NSError(domain: "second cancel did not finish", code: 1) }
        catch CaptureError.cancelled { }
        try require(!controller.hasPendingSelection, "cancellation must clear live selection")
        let live = Task { @MainActor in
            try await controller.selectLiveRegion(captureRect: CGRect(x: 120, y: 120, width: 160, height: 160))
        }
        try await waitForSelection(controller)
        let livePanel = NSApp.windows.first { $0.title == "Выбор области снимка" && $0.isVisible }!
        let liveView = livePanel.contentView as! SelectionOverlayView
        try require(controller.hasRenderedPendingSelection, "live selector must paint without waiting for a screenshot")
        try require(livePanel.backgroundColor == NSColor.clear && !livePanel.isOpaque,
                    "live selector must have a transparent background")
        let blankPoint = CGPoint(x: livePanel.frame.minX + 4, y: livePanel.frame.minY + 4)
        try await waitForMouseRouting(livePanel, at: blankPoint)
        func renderedBitmap() -> NSBitmapImageRep {
            let bitmap = liveView.bitmapImageRepForCachingDisplay(in: liveView.bounds)!
            liveView.cacheDisplay(in: liveView.bounds, to: bitmap)
            return bitmap
        }
        let bitmap = renderedBitmap()
        let blank = bitmap.colorAt(x: 4, y: 4)!.usingColorSpace(.deviceRGB)!
        try require(blank.alphaComponent > 0 && blank.alphaComponent <= 1.0 / 255 + 0.0001 && blank.redComponent > 0.99,
                    "unselected pixels need only one white alpha step: \(blank); background=\(String(describing: liveView.layer!.backgroundColor)) bounds=\(liveView.layer!.bounds) frame=\(liveView.layer!.frame) flipped=\(liveView.layer!.isGeometryFlipped) children=\(liveView.layer!.sublayers?.count ?? 0)")
        func liveMouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
                               timestamp: 0, windowNumber: livePanel.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        livePanel.sendEvent(liveMouse(.leftMouseDown, 2, 2))
        livePanel.sendEvent(liveMouse(.leftMouseDragged, 20, 20))
        livePanel.displayIfNeeded()
        CATransaction.flush()
        let selectedBitmap = renderedBitmap()
        let selectedPixel = selectedBitmap.colorAt(x: Int(2 * CGFloat(selectedBitmap.pixelsWide) / 160),
                                                    y: Int(150 * CGFloat(selectedBitmap.pixelsHigh) / 160))!.usingColorSpace(.deviceRGB)!
        try require(selectedPixel.blueComponent > selectedPixel.redComponent && selectedPixel.alphaComponent > 0.5,
                    "blue outline must occupy the rectangle indicated by the flipped view")
        for location in [40.0, 80.0, 120.0, 50.0, 20.0] {
            livePanel.sendEvent(liveMouse(.leftMouseDragged, location, location))
            livePanel.displayIfNeeded()
            CATransaction.flush()
            try require(liveView.lastPaintedArea < 160 * 160,
                        "dragging must repaint edge strips and labels rather than the whole selected area")
        }
        livePanel.sendEvent(liveMouse(.leftMouseUp, 20, 20))
        let liveRect = try await live.value
        try require(liveRect == CGRect(x: 122, y: 260, width: 18, height: 18),
                    "live selection must translate flipped local coordinates into capture coordinates")
        for (index, screen) in NSScreen.screens.enumerated() {
            let captureRect = ScreenCoordinateTransform.captureRect(fromAppKitRect: screen.frame,
                                                                   mainScreenTop: NSScreen.screens.first!.frame.maxY)
            let started = ContinuousClock.now
            let fullSize = Task { @MainActor in
                try await controller.selectLiveRegion(captureRect: captureRect)
            }
            try await waitForSelection(controller)
            let fullPanel = NSApp.windows.first { $0.title == "Выбор области снимка" && $0.isVisible }!
            try await waitForMouseRouting(fullPanel, at: CGPoint(x: screen.frame.minX + 4, y: screen.frame.minY + 4))
            try require(fullPanel.frame == screen.frame && controller.hasRenderedPendingSelection,
                        "live selection must cover the selected display with its original global coordinates")
            let elapsed = started.duration(to: .now)
            let milliseconds = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            let fullView = fullPanel.contentView as! SelectionOverlayView
            func fullMouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                                   windowNumber: fullPanel.windowNumber, context: nil,
                                   eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            fullPanel.sendEvent(fullMouse(.leftMouseDown, 4, 4))
            fullPanel.sendEvent(fullMouse(.leftMouseDragged, screen.frame.width - 4, screen.frame.height - 4))
            fullPanel.displayIfNeeded()
            CATransaction.flush()
            try require(fullView.lastPaintedArea < screen.frame.width * screen.frame.height / 4,
                        "a near-full-display drag must keep painting limited to the outline and size label: \(fullView.lastPaintedArea)")
            print("Display \(index): points=\(Int(screen.frame.width))x\(Int(screen.frame.height)) scale=\(screen.backingScaleFactor) first_ready_ms=\(milliseconds) drag_damage_points2=\(Int(fullView.lastPaintedArea))")
            controller.cancelActiveSelection()
            do { _ = try await fullSize.value; throw NSError(domain: "full-display cancellation did not finish", code: 1) }
            catch CaptureError.cancelled { }
        }
        // Reproduce a hotkey invoked from another app: establish inactivity
        // before showing the panel. Calling deactivate after showing it would
        // deliberately remove the keyboard focus we are trying to test.
        NSApp.deactivate()
        let inactiveDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while NSApp.isActive {
            try require(ContinuousClock.now < inactiveDeadline, "Escape test could not establish inactive application")
            try await Task.sleep(for: .milliseconds(10))
        }
        let escaped = Task { @MainActor in
            try await controller.selectLiveRegion(captureRect: CGRect(x: 120, y: 120, width: 160, height: 160))
        }
        try await waitForSelection(controller)
        let escapePanel = NSApp.windows.first { $0.title == "Выбор области снимка" && $0.isVisible }!
        NSApp.deactivate()
        let lostFocusDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while NSApp.isActive {
            try require(ContinuousClock.now < lostFocusDeadline, "Escape test could not deactivate the application")
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(!NSApp.isActive && escapePanel.isVisible, "Escape fallback must work from an inactive app")
        guard let escapeIdentifier = controller.selectionEscapeIdentifier else {
            throw NSError(domain: "temporary global Escape registration failed", code: 1)
        }
        var escapeEvent: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                  GetCurrentEventTime(), EventAttributes(kEventAttributeNone), &escapeEvent)
        try require(created == noErr && escapeEvent != nil, "could not create Escape Carbon event")
        defer { ReleaseEvent(escapeEvent) }
        var hotKeyID = EventHotKeyID(signature: RegionSelectionController.escapeSignature, id: escapeIdentifier)
        let status = SetEventParameter(escapeEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                      MemoryLayout<EventHotKeyID>.size, &hotKeyID)
        try require(status == noErr, "could not set Escape event ID")
        _ = SendEventToEventTarget(escapeEvent, GetApplicationEventTarget())
        do { _ = try await escaped.value; throw NSError(domain: "Escape did not finish selection", code: 1) }
        catch CaptureError.cancelled { }
        try require(!controller.hasPendingSelection, "Escape must clear the selection without a mouse press")
        try require(controller.selectionEscapeIdentifier == nil, "global Escape must be released as soon as selection closes")
        print("SelectionFocusChecks: OK (first focus, inactive drag and Escape, frozen crop, cancellation, transparent live selection, edge-only dragging)")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    @MainActor
    static func waitForSelection(_ controller: RegionSelectionController) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !controller.hasPendingSelection {
            try require(ContinuousClock.now < deadline, "selection requires an accessible graphical session")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    static func waitForMouseRouting(_ panel: NSWindow, at point: CGPoint) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) != panel.windowNumber {
            try require(ContinuousClock.now < deadline,
                        "WindowServer routing: expected=\(panel.windowNumber) actual=\(NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)) point=\(point) frame=\(panel.frame)")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
