import AppKit
import Carbon
import ScreenshotCore
@testable import ScreenshotApp

@main
struct ShelfHotKeyChecks {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let suite = "ShelfHotKeyChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPreferences(defaults: defaults)
        precondition(prefs.shelfHotKey == .defaultShelf)
        let custom = HotKey(key: "Z", keyCode: 6, modifiers: [.control, .shift])
        prefs.shelfHotKey = custom
        precondition(AppPreferences(defaults: defaults).shelfHotKey == custom)
        defaults.set(Data([0, 1]), forKey: "shelfHotKey")
        precondition(AppPreferences(defaults: defaults).shelfHotKey == .defaultShelf)

        for visible in [true, false] {
            for state: ShelfState in [.expanded, .collapsed, .hiddenUntilNextCapture, .temporarilyHidden(until: .distantFuture)] {
                let expected: ShelfState = state == .expanded && visible ? .collapsed : .expanded
                precondition(state.toggledByHotKey(windowIsVisible: visible, windowIsActive: true) == expected)
            }
        }
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 880), CGRect(x: -1920, y: 250, width: 1920, height: 1080)] {
            for pointer in [screen.origin, CGPoint(x: screen.maxX - 1, y: screen.maxY - 1), CGPoint(x: screen.midX, y: screen.midY)] {
                for size in [CGSize(width: 600, height: 700), CGSize(width: 4000, height: 4000)] {
                    let frame = ShelfPlacement.frameNearPointer(pointer, size: size, visibleFrame: screen)
                    precondition(screen.contains(frame), "Every corner and oversized shelf must stay on the pointer's screen")
                }
            }
        }

        precondition(ShelfState.expanded.toggledByHotKey(windowIsVisible: true, windowIsActive: false) == .expanded,
                     "Calling an inactive expanded shelf must reveal it, not collapse it")
        let probe = GlobalHotKeyService(signature: 0x50524F42)
        try probe.register(.defaultShelf) {}
        probe.unregister()

        let model = AppModel(preferences: prefs)
        let saved = model.preferences.shelfHotKey
        defer { model.preferences.shelfHotKey = saved }
        let shelf = ShelfPanelController(model: model, onOpenSettings: {})
        model.shelfController = shelf
        model.shelfState = .collapsed
        shelf.updatePresentation()
        let panel = NSApp.windows.first { $0.title == AppIdentity.displayName }!
        let key = HotKey(key: "F18", keyCode: 79, modifiers: [.control, .option, .shift, .command])
        precondition(model.registerShelfHotKey(key))
        try dispatch(id: 1)
        precondition(model.shelfState == .expanded && panel.isVisible)
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main!
        precondition(screen.visibleFrame.contains(panel.frame))
        let oldFrame = panel.frame
        try dispatch(id: 1)
        precondition(model.shelfState == .collapsed && panel.isVisible && panel.alphaValue == 1)
        try dispatch(id: 1, signature: 0x53485346)
        precondition(model.shelfState == .collapsed, "Capture events must not toggle the shelf")
        try dispatch(id: 1)
        precondition(model.shelfState == .expanded)
        precondition(panel.frame == oldFrame)
        panel.orderOut(nil)
        try dispatch(id: 1)
        precondition(model.shelfState == .expanded && panel.isVisible, "Hidden expanded windows must reopen")
        let blocker = GlobalHotKeyService(signature: 0x54455354)
        let occupied = HotKey(key: "F19", keyCode: 80, modifiers: [.control, .option, .shift, .command])
        try blocker.register(occupied) {}
        precondition(!model.registerShelfHotKey(occupied), "Occupied shortcuts must be rejected")
        precondition(model.activeShelfHotKey == key && model.preferences.shelfHotKey == key)
        try dispatch(id: 1)
        precondition(model.shelfState == .collapsed, "Old shortcut must survive a failed replacement")
        try dispatch(id: 1)
        let transparency = model.preferences.shelfTransparency
        let glass = model.preferences.expandedTrueLiquidGlass
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first!
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification,
            object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: other])
        precondition(model.shelfIsInactive && panel.isVisible && model.shelfState == .expanded)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { precondition(panel.alphaValue == 0.22) }
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: -1, y: -1),
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(click)
        precondition(!model.shelfIsInactive && panel.alphaValue == 1, "A local click must restore the inactive shelf")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification,
            object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: other])
        try dispatch(id: 1)
        precondition(model.shelfState == .expanded, "An inactive shelf must be summoned at the pointer")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification,
            object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        precondition(!model.shelfIsInactive && panel.alphaValue == 1)
        precondition(model.preferences.shelfTransparency == transparency && model.preferences.expandedTrueLiquidGlass == glass)
        shelf.suspend()
        try dispatch(id: 1)
        precondition(!panel.isVisible, "Hotkey must not interrupt capture suspension")
        model.shelfHotKeyService.unregister()
        blocker.unregister()
        print("ShelfHotKeyChecks: OK (Carbon toggle, conflict rollback, pointer bounds, hidden recovery, inactive glass and preference preservation)")
    }

    static func dispatch(id: UInt32, signature: OSType = 0x53485354) throws {
        var event: EventRef?
        let status = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                GetCurrentEventTime(), EventAttributes(kEventAttributeNone), &event)
        guard status == noErr, let event else { throw NSError(domain: "CreateEvent", code: Int(status)) }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: signature, id: id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          MemoryLayout<EventHotKeyID>.size, &identifier)
        _ = SendEventToEventTarget(event, GetApplicationEventTarget())
    }
}
