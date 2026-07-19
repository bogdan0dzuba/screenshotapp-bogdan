import AppKit
import Combine
import Foundation
import ScreenshotCore

@MainActor
final class AppModel: ObservableObject {
    @Published var shelfState: ShelfState = .expanded
    @Published var selectedItemID: UUID?
    @Published var statusMessage = "Готово к захвату"
    @Published var isBusy = false

    let preferences: AppPreferences
    let history: HistoryStore
    let captureService = CaptureService()
    let hotKeyService = GlobalHotKeyService()

    var shelfController: ShelfPanelController?
    var editorController: EditorWindowController?
    var pinnedController: PinnedImageController?
    var regionSelectionController: RegionSelectionController?
    var scrollCaptureController: ScrollCaptureController?
    private var pendingCaptureSource: CaptureSource?

    init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        self.history = HistoryStore(
            folderURL: preferences.captureFolder,
            maximumCount: preferences.maximumCount,
            maximumAgeDays: preferences.maximumAgeDays
        )
    }

    var selectedItem: CaptureItem? {
        if let selectedItemID, let match = history.items.first(where: { $0.id == selectedItemID }) {
            return match
        }
        return history.items.first
    }

    func start() {
        registerHotKey()
        shelfController?.updatePresentation()
    }

    func registerHotKey() {
        do {
            try hotKeyService.register(preferences.hotKey) { [weak self] in
                DispatchQueue.main.async { self?.capture(.area) }
            }
            statusMessage = "Хоткей: \(hotKeyDescription)"
        } catch {
            present(error)
        }
    }

    var hotKeyDescription: String {
        HotKeyDisplayFormatter.symbolic(preferences.hotKey)
    }

    var hotKeyReadableDescription: String {
        HotKeyDisplayFormatter.readable(preferences.hotKey)
    }

    func capture(_ mode: CaptureMode) {
        guard !isBusy else { return }
        let source = CaptureSourceProvider.current()
        isBusy = true
        statusMessage = "Выберите область…"
        shelfController?.suspend()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotApp-\(UUID().uuidString).png")

        Task {
            defer {
                isBusy = false
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            do {
                try await captureService.capture(mode, to: temporaryURL)
                let item = try history.importCapture(at: temporaryURL, source: source)
                received(item)
            } catch CaptureError.cancelled {
                statusMessage = "Захват отменен"
                shelfController?.resume()
            } catch {
                shelfController?.resume()
                present(error)
            }
        }
    }

    func startScrollingCapture() {
        guard !isBusy, let regionSelectionController else { return }
        pendingCaptureSource = CaptureSourceProvider.current()
        isBusy = true
        shelfController?.suspend()
        Task {
            do {
                let rect = try await regionSelectionController.selectRegion()
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ScreenshotScroll-\(UUID().uuidString).png")
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                try await captureService.capture(rect: rect, to: temporaryURL)
                guard let image = NSImage(contentsOf: temporaryURL),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw CaptureError.missingOutput
                }
                scrollCaptureController?.begin(rect: rect, firstFrame: cgImage, model: self)
                statusMessage = "Прокрутите содержимое и добавьте кадр"
            } catch CaptureError.cancelled {
                pendingCaptureSource = nil
                isBusy = false
                shelfController?.resume()
            } catch {
                pendingCaptureSource = nil
                isBusy = false
                shelfController?.resume()
                present(error)
            }
        }
    }

    func received(_ item: CaptureItem) {
        selectedItemID = item.id
        let completionPolicy = CaptureCompletionPolicy.standard
        if completionPolicy.revealsShelf {
            shelfState.receivedNewCapture()
        }
        statusMessage = "Снимок сохранен"
        shelfController?.resume()
        shelfController?.updatePresentation()
        if completionPolicy.opensEditor {
            edit(item)
        }
    }

    func finishScrolling(with image: CGImage) {
        defer { pendingCaptureSource = nil }
        do {
            let item = try history.importImage(image, source: pendingCaptureSource)
            isBusy = false
            received(item)
        } catch {
            isBusy = false
            shelfController?.resume()
            present(error)
        }
    }

    func cancelScrolling() {
        pendingCaptureSource = nil
        isBusy = false
        statusMessage = "Прокручиваемый захват отменен"
        shelfController?.resume()
    }

    func select(_ item: CaptureItem) {
        selectedItemID = item.id
        shelfController?.activateForKeyboard()
    }

    @discardableResult
    func copy(_ item: CaptureItem) -> Bool {
        do {
            try PasteboardService.copyImage(at: item.imageURL)
            statusMessage = "Скопировано - вставьте ⌘V"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveAs(_ item: CaptureItem) {
        let panel = NSSavePanel()
        panel.title = "Сохранить снимок"
        panel.nameFieldStringValue = item.imageURL.lastPathComponent
        panel.allowedContentTypes = preferences.imageFormat == .png ? [.png] : [.jpeg]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            guard let image = NSImage(contentsOf: item.imageURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try HistoryStore.write(cgImage, to: destination, format: preferences.imageFormat)
            statusMessage = "Сохранено: \(destination.lastPathComponent)"
        } catch { present(error) }
    }

    func edit(_ item: CaptureItem) {
        editorController?.open(item: item, model: self)
    }

    func recognizeText(_ item: CaptureItem) {
        statusMessage = "Распознаю текст…"
        guard let image = NSImage(contentsOf: item.imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            present(CocoaError(.fileReadCorruptFile))
            return
        }
        Task.detached {
            do {
                let text = try OCRService.recognizeText(in: cgImage)
                await MainActor.run {
                    PasteboardService.copyText(text)
                    self.statusMessage = text.isEmpty ? "Текст не найден" : "Текст скопирован"
                }
            } catch {
                await MainActor.run { self.present(error) }
            }
        }
    }

    func pin(_ item: CaptureItem) {
        pinnedController?.pin(item: item)
    }

    func reveal(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.imageURL])
    }

    func delete(_ item: CaptureItem) {
        do {
            try history.delete(item)
            selectedItemID = history.items.first?.id
            statusMessage = "Перемещено в Корзину"
        } catch { present(error) }
    }

    func clearHistory() {
        do {
            try history.clearAll()
            selectedItemID = nil
            statusMessage = "История очищена"
        } catch { present(error) }
    }

    func collapseShelf() {
        shelfState.collapse()
        shelfController?.updatePresentation()
    }

    func expandShelf() {
        shelfState.expand()
        shelfController?.updatePresentation()
    }

    func hideShelf(for interval: TimeInterval?) {
        if let interval {
            shelfState = .temporarilyHidden(until: Date().addingTimeInterval(interval))
        } else {
            shelfState = .hiddenUntilNextCapture
        }
        shelfController?.updatePresentation()
    }

    func showShelf() {
        shelfState = .expanded
        shelfController?.resume()
        shelfController?.updatePresentation()
    }

    func chooseCaptureFolder() {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку для снимков"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.captureFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.captureFolder = url
        reloadPreferences()
    }

    func copyFolderPath() {
        PasteboardService.copyText(preferences.captureFolder.path)
        statusMessage = "Путь к папке скопирован"
    }

    func reloadPreferences() {
        do {
            try history.update(
                folderURL: preferences.captureFolder,
                maximumCount: preferences.maximumCount,
                maximumAgeDays: preferences.maximumAgeDays
            )
            registerHotKey()
        } catch { present(error) }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func present(_ error: Error) {
        statusMessage = error.localizedDescription
        let alert = NSAlert(error: error)
        alert.messageText = "Скриншот не готов"
        alert.addButton(withTitle: "ОК")
        alert.addButton(withTitle: "Настройки доступа")
        if alert.runModal() == .alertSecondButtonReturn {
            openScreenRecordingSettings()
        }
    }
}
