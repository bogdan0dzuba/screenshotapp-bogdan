import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private var hasBeenShown = false

    init(model: AppModel, updateService: UpdateService) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ScreenshotApp.Settings")
        window.contentView = NSHostingView(
            rootView: SettingsView(model: model, updateService: updateService)
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if !hasBeenShown, !window.setFrameUsingName("ScreenshotApp.Settings") {
            window.center()
        }
        hasBeenShown = true
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
