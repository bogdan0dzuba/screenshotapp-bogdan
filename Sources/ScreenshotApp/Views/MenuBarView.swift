import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateService: UpdateService
    let onOpenSettings: () -> Void

    var body: some View {
        Button("Снять область  \(model.hotKeyDescription)") { model.capture(.area) }
        Button("Снять окно") { model.capture(.window) }
        Button("Снять весь экран") { model.capture(.fullScreen) }
        Button("Снять с прокруткой") { model.startScrollingCapture() }
        Divider()
        Button("Показать полку") { model.showShelf() }
        Button("Открыть папку") { NSWorkspace.shared.open(model.preferences.captureFolder) }
        Button("Скопировать путь папки") { model.copyFolderPath() }
        Divider()
        Button("Проверить обновления…") { updateService.checkForUpdates() }
        Button("Настройки…", action: onOpenSettings)
        Divider()
        Button("Завершить \(AppIdentity.displayName)") { NSApp.terminate(nil) }
    }
}
