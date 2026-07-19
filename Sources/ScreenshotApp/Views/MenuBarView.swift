import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

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
        Button("Проверить обновления…") {
            NSWorkspace.shared.open(
                URL(string: "https://github.com/bogdan0dzuba/screenshotapp-bogdan/releases/latest")!
            )
        }
        SettingsLink { Text("Настройки…") }
        Divider()
        Button("Завершить ScreenshotApp") { NSApp.terminate(nil) }
    }
}
