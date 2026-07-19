import AppKit
import ScreenshotCore
import SwiftUI

@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: NSPanel
    private let sizeStore: ShelfWindowSizeStore
    private var expandedSize: CGSize
    private var isSuspended = false
    private var hasBeenPresented = false
    private var isApplyingPresentation = false
    private var copyEventMonitor: Any?
    private var wakeTask: Task<Void, Never>?

    init(model: AppModel, sizeStore: ShelfWindowSizeStore = ShelfWindowSizeStore()) {
        self.model = model
        self.sizeStore = sizeStore
        let storedSize = sizeStore.load()
        expandedSize = storedSize
        let initialPanelSize = ShelfMetrics.constrainedExpandedSize(
            storedSize,
            visibleSize: NSScreen.main?.visibleFrame.size ?? storedSize
        )
        panel = KeyableShelfPanel(
            contentRect: CGRect(origin: .zero, size: initialPanelSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = ShelfMetrics.minimumExpandedSize
        panel.delegate = self
        panel.contentView = ShelfHostingView(rootView: ShelfView(model: model))
        copyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  ShelfKeyboardShortcut.shouldCopy(
                    key: event.charactersIgnoringModifiers ?? "",
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    eventWindowNumber: event.windowNumber,
                    panelWindowNumber: self.panel.windowNumber,
                    panelIsKey: self.panel.isKeyWindow
                  ),
                  let item = self.model.selectedItem else {
                return event
            }
            self.model.copy(item)
            return nil
        }
    }

    deinit {
        if let copyEventMonitor {
            NSEvent.removeMonitor(copyEventMonitor)
        }
    }

    func suspend() {
        isSuspended = true
        panel.orderOut(nil)
    }

    func resume() {
        isSuspended = false
        updatePresentation()
    }

    func activateForKeyboard() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func updatePresentation() {
        wakeTask?.cancel()
        guard !isSuspended else {
            panel.orderOut(nil)
            return
        }

        switch model.shelfState {
        case .expanded:
            configureResizing(isEnabled: true)
            show(size: expandedSize)
        case .collapsed:
            configureResizing(isEnabled: false)
            show(size: ShelfMetrics.collapsedSize)
        case let .temporarilyHidden(until):
            if until <= Date() {
                model.shelfState = .collapsed
                configureResizing(isEnabled: false)
                show(size: ShelfMetrics.collapsedSize)
            } else {
                panel.orderOut(nil)
                let delay = until.timeIntervalSinceNow
                wakeTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.model.shelfState = .collapsed
                    self?.updatePresentation()
                }
            }
        case .hiddenUntilNextCapture:
            panel.orderOut(nil)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard ShelfWindowResizePolicy.shouldPersist(
            isExpanded: model.shelfState == .expanded,
            isApplyingPresentation: isApplyingPresentation,
            isLiveResize: panel.inLiveResize
        ) else { return }
        persistExpandedSize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard model.shelfState == .expanded, !isApplyingPresentation else { return }
        persistExpandedSize()
    }

    private func persistExpandedSize() {
        guard let screen = targetScreen() else { return }
        expandedSize = ShelfMetrics.constrainedExpandedSize(panel.frame.size, visibleSize: screen.visibleFrame.size)
        sizeStore.save(expandedSize)
    }

    private func show(size: CGSize) {
        guard let screen = targetScreen() else { return }
        let targetSize = model.shelfState == .expanded
            ? ShelfMetrics.constrainedExpandedSize(size, visibleSize: screen.visibleFrame.size)
            : ShelfMetrics.collapsedSize
        let frame = ShelfPlacement.resizedFrame(
            currentFrame: panel.frame,
            targetSize: targetSize,
            visibleFrame: screen.visibleFrame,
            hasBeenPresented: hasBeenPresented
        )
        isApplyingPresentation = true
        panel.setFrame(frame, display: true, animate: false)
        isApplyingPresentation = false
        hasBeenPresented = true
        panel.orderFrontRegardless()
    }

    private func configureResizing(isEnabled: Bool) {
        if isEnabled {
            panel.styleMask.insert(.resizable)
            let visibleSize = targetScreen()?.visibleFrame.size ?? ShelfMetrics.minimumExpandedSize
            panel.minSize = CGSize(
                width: min(ShelfMetrics.minimumExpandedSize.width, visibleSize.width),
                height: min(ShelfMetrics.minimumExpandedSize.height, visibleSize.height)
            )
        } else {
            panel.minSize = ShelfMetrics.collapsedSize
            panel.styleMask.remove(.resizable)
        }
    }

    private func targetScreen() -> NSScreen? {
        if hasBeenPresented {
            let currentFrame = panel.frame
            let intersecting = NSScreen.screens
                .map { screen in
                    let intersection = currentFrame.intersection(screen.frame)
                    let area = intersection.isNull ? 0 : intersection.width * intersection.height
                    return (screen: screen, area: area)
                }
                .max { $0.area < $1.area }
            if let intersecting, intersecting.area > 0 {
                return intersecting.screen
            }
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }
}

private final class KeyableShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ShelfHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
