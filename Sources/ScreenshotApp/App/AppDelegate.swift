import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let shelf = ShelfPanelController(model: model)
        model.shelfController = shelf
        model.editorController = EditorWindowController()
        model.pinnedController = PinnedImageController()
        model.regionSelectionController = RegionSelectionController()
        model.scrollCaptureController = ScrollCaptureController()
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
