import ScreenshotCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateService: UpdateService
    @ObservedObject private var preferences: AppPreferences
    @State private var draftHotKeyLetter: String
    @State private var draftUseCommand: Bool
    @State private var draftUseShift: Bool
    @State private var draftUseOption: Bool
    @State private var draftUseControl: Bool

    init(model: AppModel, updateService: UpdateService) {
        self.model = model
        self.updateService = updateService
        _preferences = ObservedObject(wrappedValue: model.preferences)
        _draftHotKeyLetter = State(initialValue: model.preferences.hotKeyLetter)
        _draftUseCommand = State(initialValue: model.preferences.useCommand)
        _draftUseShift = State(initialValue: model.preferences.useShift)
        _draftUseOption = State(initialValue: model.preferences.useOption)
        _draftUseControl = State(initialValue: model.preferences.useControl)
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
        .onAppear { synchronizeHotKeyDraft() }
        .onChange(of: model.activeHotKey) { _, _ in synchronizeHotKeyDraft() }
    }

    private var generalTab: some View {
        Form {
            Section("Горячая клавиша") {
                Text("Выберите клавиши, которые нужно нажать одновременно.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    GridRow {
                        Toggle("Command (⌘)", isOn: $draftUseCommand)
                        Toggle("Shift (⇧)", isOn: $draftUseShift)
                    }
                    GridRow {
                        Toggle("Option (⌥)", isOn: $draftUseOption)
                        Toggle("Control (⌃)", isOn: $draftUseControl)
                    }
                }
                .toggleStyle(.checkbox)
                Picker("Клавиша", selection: $draftHotKeyLetter) {
                    ForEach(preferences.availableLetters, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 220, alignment: .leading)
                LabeledContent("Активная комбинация") {
                    Text(model.hotKeyReadableDescription)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                }
                LabeledContent("Новая комбинация") {
                    Text(HotKeyDisplayFormatter.readable(hotKeyDraft))
                        .fontWeight(.semibold)
                        .textSelection(.enabled)
                }
                Button("Применить сочетание") {
                    if !model.registerHotKey(hotKeyDraft) {
                        synchronizeHotKeyDraft()
                    }
                }
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
            Section("Обновления") {
                Toggle(
                    "Автоматически проверять обновления",
                    isOn: $updateService.automaticallyChecksForUpdates
                )
                Toggle(
                    "Автоматически скачивать обновления",
                    isOn: $updateService.automaticallyDownloadsUpdates
                )
                .disabled(!updateService.automaticallyChecksForUpdates)
                Button("Проверить сейчас…") { updateService.checkForUpdates() }
                Text("Проверка выполняется при запуске и затем раз в сутки. Новая версия автоматически загружается из GitHub Releases, проверяется криптографической подписью, устанавливается и быстро перезапускает приложение.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("О приложении") {
                LabeledContent("Название") {
                    Text(AppIdentity.displayName)
                }
                LabeledContent("Установленная версия") {
                    Text(AppIdentity.versionDescription)
                        .font(.body.monospacedDigit())
                        .textSelection(.enabled)
                }
            }
            Section("Внешний вид") {
                LabeledContent("Прозрачность полки") {
                    HStack(spacing: 10) {
                        Slider(value: $preferences.shelfTransparency, in: 0...1)
                            .frame(width: 190)
                        Text("\(Int((preferences.shelfTransparency * 100).rounded()))%")
                            .font(.body.monospacedDigit())
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Text("0% - плотнее, 100% - прозрачнее. Текст, иконки и снимки не бледнеют.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var hotKeyDraft: HotKey {
        var modifiers: HotKeyModifiers = []
        if draftUseCommand { modifiers.insert(.command) }
        if draftUseShift { modifiers.insert(.shift) }
        if draftUseOption { modifiers.insert(.option) }
        if draftUseControl { modifiers.insert(.control) }
        return HotKey(
            key: draftHotKeyLetter,
            keyCode: AppPreferences.keyCodes[draftHotKeyLetter] ?? 0,
            modifiers: modifiers
        )
    }

    private func synchronizeHotKeyDraft() {
        let hotKey = model.activeHotKey ?? preferences.hotKey
        draftHotKeyLetter = hotKey.key
        draftUseCommand = hotKey.modifiers.contains(.command)
        draftUseShift = hotKey.modifiers.contains(.shift)
        draftUseOption = hotKey.modifiers.contains(.option)
        draftUseControl = hotKey.modifiers.contains(.control)
    }

    private var historyTab: some View {
        Form {
            Section("Хранение") {
                Toggle(
                    "Автоматически удалять старые снимки",
                    isOn: $preferences.automaticallyDeletesOldCaptures
                )
                Group {
                    Stepper(
                        "Не больше \(preferences.maximumCount) снимков",
                        value: $preferences.maximumCount,
                        in: 1...HistoryRetentionPolicy.maximumCaptures
                    )
                    Stepper(
                        "Не старше \(preferences.maximumAgeDays) дней",
                        value: $preferences.maximumAgeDays,
                        in: 1...365
                    )
                }
                .disabled(!preferences.automaticallyDeletesOldCaptures)
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
