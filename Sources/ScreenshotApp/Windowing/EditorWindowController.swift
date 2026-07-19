import AppKit
import ScreenshotCore
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var windows: [UUID: NSWindow] = [:]
    private var sessions: [UUID: EditorSession] = [:]
    private var models: [UUID: AppModel] = [:]
    private var copyEventMonitor: Any?

    override init() {
        super.init()
        copyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  ShelfKeyboardShortcut.isCopy(
                    key: event.charactersIgnoringModifiers ?? "",
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags
                  ),
                  let itemID = self.sessionID(forWindowNumber: event.windowNumber) else {
                return event
            }
            if event.modifierFlags.contains(.command), event.window?.firstResponder is NSTextView {
                return event
            }
            self.copySession(itemID)
            return nil
        }
    }

    deinit {
        if let copyEventMonitor {
            NSEvent.removeMonitor(copyEventMonitor)
        }
    }

    func open(item: CaptureItem, model: AppModel) {
        if let existing = windows[item.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let session = EditorSession(item: item, model: model) else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        let visibleSize = screen?.visibleFrame.size ?? CGSize(width: 1_440, height: 900)
        let contentSize = EditorWindowLayout.contentSize(
            image: CanvasSize(
                width: Double(session.windowImageSize.width),
                height: Double(session.windowImageSize.height)
            ),
            visibleSize: CanvasSize(width: Double(visibleSize.width), height: Double(visibleSize.height))
        )
        let window = NSWindow(
            contentRect: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(contentSize.width),
                height: CGFloat(contentSize.height)
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        window.title = "Редактор снимка"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(
            width: CGFloat(EditorWindowLayout.minimumContentSize.width),
            height: CGFloat(EditorWindowLayout.minimumContentSize.height)
        )
        window.contentView = NSHostingView(rootView: EditorView(
            session: session,
            copyAction: { [weak self] in self?.copySession(item.id) }
        ))
        window.delegate = self
        if let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(CGPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        windows[item.id] = window
        sessions[item.id] = session
        models[item.id] = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let identifier = window.identifier?.rawValue,
              let id = UUID(uuidString: identifier) else { return }
        windows[id] = nil
        sessions[id] = nil
        models[id] = nil
    }

    private func sessionID(forWindowNumber windowNumber: Int) -> UUID? {
        windows.first(where: { $0.value.windowNumber == windowNumber })?.key
    }

    private func copySession(_ itemID: UUID) {
        guard let session = sessions[itemID], session.copy() else { return }
        if models[itemID]?.preferences.closeEditorAfterCopy == true {
            windows[itemID]?.performClose(nil)
        }
    }
}
