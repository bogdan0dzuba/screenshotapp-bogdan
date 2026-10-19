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
    private var localActivityMonitor: Any?
    private var globalActivityMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var collapseAfterFullScreen = false
    private var wakeTask: Task<Void, Never>?

    init(
        model: AppModel,
        sizeStore: ShelfWindowSizeStore = ShelfWindowSizeStore(),
        onOpenSettings: @escaping () -> Void
    ) {
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
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary, .transient]
        panel.title = AppIdentity.displayName
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = ShelfMetrics.minimumExpandedSize
        panel.delegate = self
        panel.contentView = ShelfHostingView(
            rootView: ShelfView(
                model: model,
                onOpenSettings: onOpenSettings,
                onClose: { [weak panel] in panel?.orderOut(nil) },
                onMinimize: { [weak panel] in panel?.miniaturize(nil) },
                onToggleFullScreen: { [weak self] in self?.toggleFullScreen(nil) }
            )
        )
        setStandardWindowControlsVisible(false)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                self?.setInactive(app.processIdentifier != ProcessInfo.processInfo.processIdentifier)
            }
        }
        globalActivityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.setInactive(true) }
        }
        localActivityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.windowNumber == self.panel.windowNumber {
                self.setInactive(false)
            }
            return event
        }
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
        setInactive(NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier)
    }

    deinit {
        if let localActivityMonitor { NSEvent.removeMonitor(localActivityMonitor) }
        if let globalActivityMonitor { NSEvent.removeMonitor(globalActivityMonitor) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let copyEventMonitor {
            NSEvent.removeMonitor(copyEventMonitor)
        }
    }

    private func setInactive(_ inactive: Bool) {
        let inactive = inactive && model.shelfState == .expanded
        model.shelfIsInactive = inactive
        panel.alphaValue = 1
        configureWindowLevel()
        if inactive && panel.isVisible && !panel.styleMask.contains(.fullScreen) {
            panel.orderBack(nil)
        }
    }

    private func configureWindowLevel() {
        let compact = model.shelfState == .collapsed && !panel.styleMask.contains(.fullScreen)
        panel.isFloatingPanel = compact
        panel.level = compact ? .floating : .normal
    }

    func toggleNearPointer() {
        guard !isSuspended else { return }
        let next = model.shelfState.toggledByHotKey(windowIsVisible: panel.isVisible && !panel.isMiniaturized,
                                                     windowIsActive: !model.shelfIsInactive)
        if next == .collapsed, panel.styleMask.contains(.fullScreen) {
            collapseAfterFullScreen = true
            panel.toggleFullScreen(nil)
            return
        }
        model.shelfState = next
        setInactive(false)
        updatePresentation()
        if next == .expanded {
            let pointer = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
            let frame = ShelfPlacement.frameNearPointer(pointer, size: expandedSize, visibleFrame: screen.visibleFrame)
            isApplyingPresentation = true
            panel.setFrame(frame, display: true)
            isApplyingPresentation = false
            activateForKeyboard()
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
        setInactive(false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func updatePresentation() {
        wakeTask?.cancel()
        guard !isSuspended else {
            panel.orderOut(nil)
            return
        }

        if model.shelfState != .expanded { setInactive(false) }
        configureWindowLevel()
        switch model.shelfState {
        case .expanded:
            configureWindowChrome(
                showsCustomControls: ShelfWindowChromePolicy.showsCustomControls(in: model.shelfState)
            )
            configureResizing(isEnabled: true)
            show(size: expandedSize)
        case .collapsed:
            configureWindowChrome(
                showsCustomControls: ShelfWindowChromePolicy.showsCustomControls(in: model.shelfState)
            )
            configureResizing(isEnabled: false)
            show(size: ShelfMetrics.collapsedSize)
        case let .temporarilyHidden(until):
            setStandardWindowControlsVisible(false)
            if until <= Date() {
                model.shelfState = .collapsed
                configureWindowChrome(showsCustomControls: false)
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
            setStandardWindowControlsVisible(false)
            panel.orderOut(nil)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard ShelfWindowResizePolicy.shouldPersist(
            isExpanded: model.shelfState == .expanded,
            isApplyingPresentation: isApplyingPresentation,
            isLiveResize: panel.inLiveResize,
            isFullScreen: panel.styleMask.contains(.fullScreen)
        ) else { return }
        persistExpandedSize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard model.shelfState == .expanded,
              !isApplyingPresentation,
              !panel.styleMask.contains(.fullScreen) else { return }
        persistExpandedSize()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        panel.isFloatingPanel = false
        panel.level = .normal
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if collapseAfterFullScreen {
            collapseAfterFullScreen = false
            model.shelfState = .collapsed
            setInactive(false)
        }
        configureWindowLevel()
        updatePresentation()
    }

    private func persistExpandedSize() {
        guard let screen = targetScreen() else { return }
        expandedSize = ShelfMetrics.constrainedExpandedSize(panel.frame.size, visibleSize: screen.visibleFrame.size)
        sizeStore.save(expandedSize)
    }

    private func show(size: CGSize) {
        guard let screen = targetScreen() else { return }
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
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
        if model.shelfState == .expanded && model.shelfIsInactive {
            panel.orderBack(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func configureWindowChrome(showsCustomControls: Bool) {
        if showsCustomControls {
            panel.styleMask.remove(.borderless)
            panel.styleMask.insert(.titled)
            panel.styleMask.insert(.closable)
            panel.styleMask.insert(.miniaturizable)
            panel.styleMask.insert(.fullSizeContentView)
        } else {
            setStandardWindowControlsVisible(false)
            panel.styleMask.remove(.titled)
            panel.styleMask.remove(.closable)
            panel.styleMask.remove(.miniaturizable)
            panel.styleMask.remove(.fullSizeContentView)
            panel.styleMask.insert(.borderless)
        }
        setStandardWindowControlsVisible(false)
    }

    private func setStandardWindowControlsVisible(_ isVisible: Bool) {
        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            panel.standardWindowButton(buttonType)?.isHidden = !isVisible
            panel.standardWindowButton(buttonType)?.isEnabled = isVisible
        }
    }

    @objc private func toggleFullScreen(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.toggleFullScreen(sender)
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
    override var canBecomeMain: Bool { true }
}

private final class ShelfHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
}
