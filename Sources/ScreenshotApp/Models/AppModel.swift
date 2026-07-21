import AppKit
import Combine
import Foundation
import ScreenshotCore

@MainActor
final class AppModel: ObservableObject {
    private struct CaptureRequest {
        var id: UUID
        var sequence: UInt64
        var source: CaptureSource?
        var temporaryURL: URL
    }

    private struct PendingCaptureResult {
        var sequence: UInt64
        var item: CaptureItem
    }

    @Published var shelfState: ShelfState = .expanded
    @Published var selectedItemID: UUID?
    @Published var statusMessage = "Готово к захвату"
    @Published private(set) var isBusy = false

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
    private var pendingScrollCaptureID: UUID?
    private var pendingScrollCaptureSequence: UInt64?
    private var captureActivity = CaptureActivityState()
    private var pendingCaptureResults: [PendingCaptureResult] = []
    private var nextCaptureSequence: UInt64 = 0
    private var latestPresentedCaptureSequence: UInt64 = 0

    init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        self.history = HistoryStore(
            folderURL: preferences.captureFolder,
            maximumCount: preferences.maximumCount,
            maximumAgeDays: preferences.maximumAgeDays,
            automaticCleanupEnabled: preferences.automaticallyDeletesOldCaptures
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
        do {
            try history.reload()
        } catch {
            statusMessage = error.localizedDescription
        }
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
        switch mode {
        case .area:
            captureArea()
        case .window, .fullScreen:
            captureWithSystemUI(mode)
        }
    }

    private func captureArea() {
        guard let regionSelectionController else {
            CaptureTelemetry.logger.error("area_capture_unavailable")
            return
        }
        guard let request = prepareCaptureRequest() else {
            CaptureTelemetry.logger.notice("area_capture_ignored_busy")
            return
        }
        CaptureTelemetry.logger.info("area_capture_started")
        let captureService = captureService
        let captureTask = Task { @MainActor in
            let selection = try await regionSelectionController.selectRegion(using: captureService)
            try await Task.detached(priority: .userInitiated) {
                try captureService.write(selection.image, to: request.temporaryURL)
            }.value
        }
        finishCapture(request, task: captureTask)
    }

    private func captureWithSystemUI(_ mode: CaptureMode) {
        guard let request = prepareCaptureRequest() else { return }
        let captureService = captureService
        let captureTask = Task.detached(priority: .userInitiated) {
            try await captureService.capture(mode, to: request.temporaryURL)
        }
        finishCapture(request, task: captureTask)
    }

    private func prepareCaptureRequest() -> CaptureRequest? {
        let id = UUID()
        guard captureActivity.beginCapture(id: id) else { return nil }
        let sequence = makeCaptureSequence()
        updateBusyState()
        let source = CaptureSourceProvider.current()
        shelfController?.suspend()
        statusMessage = "Выберите область…"
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotApp-\(UUID().uuidString).png")
        return CaptureRequest(id: id, sequence: sequence, source: source, temporaryURL: temporaryURL)
    }

    private func finishCapture(
        _ request: CaptureRequest,
        task captureTask: Task<Void, Error>
    ) {
        Task {
            defer { try? FileManager.default.removeItem(at: request.temporaryURL) }
            let capturedAt: Date
            do {
                try await captureTask.value
                capturedAt = Date()
                guard beginImport(for: request.id) else { return }
            } catch CaptureError.cancelled {
                cancelCapture(id: request.id)
                statusMessage = "Захват отменен"
                resumeShelfAndPresentPendingResults()
                return
            } catch {
                cancelCapture(id: request.id)
                resumeShelfAndPresentPendingResults()
                present(error)
                return
            }

            do {
                let item = try await history.importCapture(
                    at: request.temporaryURL,
                    source: request.source,
                    capturedAt: capturedAt
                )
                finishImport(id: request.id)
                enqueueCaptureResult(item, sequence: request.sequence)
            } catch {
                finishImport(id: request.id)
                if captureActivity.canPresentCaptureResults {
                    shelfController?.resume()
                    present(error)
                } else {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func startScrollingCapture() {
        guard let regionSelectionController else { return }
        let captureID = UUID()
        guard captureActivity.beginCapture(id: captureID) else { return }
        let captureSequence = makeCaptureSequence()
        updateBusyState()
        pendingScrollCaptureID = captureID
        pendingScrollCaptureSequence = captureSequence
        pendingCaptureSource = CaptureSourceProvider.current()
        shelfController?.suspend()
        Task {
            do {
                let selection = try await regionSelectionController.selectRegion(using: captureService)
                scrollCaptureController?.begin(
                    rect: selection.rect,
                    firstFrame: selection.image,
                    model: self
                )
                statusMessage = "Прокрутите содержимое и добавьте кадр"
            } catch CaptureError.cancelled {
                pendingCaptureSource = nil
                pendingScrollCaptureID = nil
                pendingScrollCaptureSequence = nil
                cancelCapture(id: captureID)
                resumeShelfAndPresentPendingResults()
            } catch {
                pendingCaptureSource = nil
                pendingScrollCaptureID = nil
                pendingScrollCaptureSequence = nil
                cancelCapture(id: captureID)
                resumeShelfAndPresentPendingResults()
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
        if completionPolicy.opensEditor {
            edit(item)
        }
    }

    func finishScrolling(with image: CGImage) {
        guard let captureID = pendingScrollCaptureID,
              let captureSequence = pendingScrollCaptureSequence else { return }
        pendingScrollCaptureID = nil
        pendingScrollCaptureSequence = nil
        let source = pendingCaptureSource
        pendingCaptureSource = nil
        let capturedAt = Date()
        guard beginImport(for: captureID) else { return }
        Task {
            do {
                let item = try await history.importImage(
                    image,
                    source: source,
                    capturedAt: capturedAt
                )
                finishImport(id: captureID)
                enqueueCaptureResult(item, sequence: captureSequence)
            } catch {
                finishImport(id: captureID)
                if captureActivity.canPresentCaptureResults {
                    shelfController?.resume()
                    present(error)
                } else {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelScrolling() {
        if let captureID = pendingScrollCaptureID {
            cancelCapture(id: captureID)
        }
        pendingScrollCaptureID = nil
        pendingScrollCaptureSequence = nil
        pendingCaptureSource = nil
        statusMessage = "Прокручиваемый захват отменен"
        resumeShelfAndPresentPendingResults()
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
        let storageChangeID = UUID()
        guard captureActivity.beginStorageChange(id: storageChangeID) else {
            statusMessage = "Дождитесь завершения захвата и сохранения снимка"
            return
        }
        updateBusyState()
        defer {
            captureActivity.finishStorageChange(id: storageChangeID)
            updateBusyState()
            presentPendingCaptureResultsIfPossible()
        }
        let panel = NSOpenPanel()
        panel.title = "Выберите папку для снимков"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.captureFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.captureFolder = url
        applyPreferences()
    }

    func copyFolderPath() {
        PasteboardService.copyText(preferences.captureFolder.path)
        statusMessage = "Путь к папке скопирован"
    }

    func reloadPreferences() {
        guard captureActivity.canChangeStorage else {
            statusMessage = "Дождитесь завершения захвата и сохранения снимка"
            return
        }
        applyPreferences()
    }

    private func applyPreferences() {
        do {
            try history.update(
                folderURL: preferences.captureFolder,
                maximumCount: preferences.maximumCount,
                maximumAgeDays: preferences.maximumAgeDays,
                automaticCleanupEnabled: preferences.automaticallyDeletesOldCaptures
            )
            registerHotKey()
        } catch { present(error) }
    }

    private func beginImport(for captureID: UUID) -> Bool {
        guard captureActivity.finishCaptureAndBeginImport(id: captureID) else { return false }
        updateBusyState()
        presentPendingCaptureResultsIfPossible()
        return true
    }

    private func cancelCapture(id: UUID) {
        captureActivity.cancelCapture(id: id)
        updateBusyState()
    }

    private func finishImport(id: UUID) {
        captureActivity.finishImport(id: id)
        updateBusyState()
    }

    private func updateBusyState() {
        isBusy = !captureActivity.canStartCapture
    }

    private func makeCaptureSequence() -> UInt64 {
        nextCaptureSequence &+= 1
        return nextCaptureSequence
    }

    private func enqueueCaptureResult(_ item: CaptureItem, sequence: UInt64) {
        pendingCaptureResults.append(PendingCaptureResult(sequence: sequence, item: item))
        presentPendingCaptureResultsIfPossible()
    }

    private func resumeShelfAndPresentPendingResults() {
        guard captureActivity.canPresentCaptureResults else { return }
        shelfController?.resume()
        presentPendingCaptureResultsIfPossible()
    }

    private func presentPendingCaptureResultsIfPossible() {
        guard captureActivity.canPresentCaptureResults, !pendingCaptureResults.isEmpty else { return }
        let pending = pendingCaptureResults
        pendingCaptureResults.removeAll()
        guard let sequence = CaptureResultOrder.sequenceToPresent(
            pending: pending.map(\.sequence),
            latestPresented: latestPresentedCaptureSequence
        ), let result = pending.first(where: { $0.sequence == sequence }) else { return }
        latestPresentedCaptureSequence = sequence
        received(result.item)
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
