import ScreenshotCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var preferences: AppPreferences

    init(model: AppModel) {
        self.model = model
        _preferences = ObservedObject(wrappedValue: model.preferences)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Основные", systemImage: "gearshape") }
            historyTab
                .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
            accessTab
                .tabItem { Label("Доступ", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 350)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section("Горячая клавиша") {
                Text("Выберите клавиши, которые нужно нажать одновременно.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    GridRow {
                        Toggle("Command (⌘)", isOn: $preferences.useCommand)
                        Toggle("Shift (⇧)", isOn: $preferences.useShift)
                    }
                    GridRow {
                        Toggle("Option (⌥)", isOn: $preferences.useOption)
                        Toggle("Control (⌃)", isOn: $preferences.useControl)
                    }
                }
                .toggleStyle(.checkbox)
                Picker("Клавиша", selection: $preferences.hotKeyLetter) {
                    ForEach(preferences.availableLetters, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 220, alignment: .leading)
                LabeledContent("Текущая комбинация") {
                    Text(model.hotKeyReadableDescription)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                }
                Button("Применить сочетание") { model.registerHotKey() }
            }
            Section("Сохранение") {
                LabeledContent("Папка") {
                    Text(preferences.captureFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 330, alignment: .trailing)
                }
                HStack {
                    Button("Выбрать папку…") { model.chooseCaptureFolder() }
                    Button("Скопировать путь") { model.copyFolderPath() }
                    Button("Открыть") { NSWorkspace.shared.open(preferences.captureFolder) }
                }
                Picker("Формат «Сохранить как»", selection: $preferences.imageFormat) {
                    ForEach(AppPreferences.ImageFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
            }
            Section("Редактор") {
                Toggle("Закрывать редактор после копирования", isOn: $preferences.closeEditorAfterCopy)
                Text("Работает для Ctrl+C, ⌘C и кнопки «Копировать». При ошибке редактор останется открытым.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var historyTab: some View {
        Form {
            Section("Хранение") {
                Stepper(
                    "Не больше \(preferences.maximumCount) снимков",
                    value: $preferences.maximumCount,
                    in: 1...HistoryRetentionPolicy.maximumCaptures
                )
                Stepper("Не старше \(preferences.maximumAgeDays) дней", value: $preferences.maximumAgeDays, in: 1...365)
                Button("Применить и перечитать папку") { model.reloadPreferences() }
            }
            Section("Очистка") {
                Button("Очистить историю…", role: .destructive) { model.clearHistory() }
            }
            Section("Доступ агентам") {
                Text("Снимки сохраняются обычными PNG-файлами. Скопируйте путь и передайте его агенту, либо прикрепите нужный файл из полки.")
                    .foregroundStyle(.secondary)
                Text(preferences.captureFolder.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var accessTab: some View {
        Form {
            Section("Разрешение macOS") {
                Text("Для снимков приложению требуется разрешение «Запись экрана». Изображения и распознанный текст никуда не отправляются.")
                    .foregroundStyle(.secondary)
                Button("Открыть настройки записи экрана") { model.openScreenRecordingSettings() }
            }
            Section("Приватность") {
                Label("Без облака и аккаунта", systemImage: "icloud.slash")
                Label("OCR выполняется на Mac", systemImage: "lock.shield")
                Label("Удаление отправляет файлы в Корзину", systemImage: "trash")
            }
        }
        .formStyle(.grouped)
    }
}
