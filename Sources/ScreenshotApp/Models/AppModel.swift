import AppKit
import Combine
import Foundation
import ScreenshotCore
import ScreenCaptureKit

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
    @Published private(set) var activeHotKey: HotKey?

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
    private var activeAreaCaptureTask: Task<Void, Error>?
    private var activeAreaCaptureID: UUID?
    private var restartAreaCaptureAfterCancellation = false
    private var areaHotKeyAttemptCount = 0
    private let systemContentCapture = SystemContentCaptureController()
    private var lastCaptureMode: CaptureMode = .area
    private var lastCaptureWasScrolling = false
    private var isCheckingScreenCapturePermission = false

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
        let preferred = preferences.hotKey
        var lastError: Error?

        for candidate in HotKeyStartupPolicy.candidates(preferred: preferred) {
            do {
                try activateHotKey(candidate)
                if candidate != preferred {
                    statusMessage = "Сохраненный хоткей занят. Включен стандартный: \(hotKeyDescription)"
                }
                return
            } catch {
                lastError = error
            }
        }

        activeHotKey = hotKeyService.registeredHotKey
        if let activeHotKey {
            preferences.setHotKey(activeHotKey)
        }
        if let lastError {
            presentHotKeyRegistrationError(lastError)
        }
    }

    @discardableResult
    func registerHotKey(_ candidateHotKey: HotKey) -> Bool {
        let previousHotKey = activeHotKey
        do {
            try activateHotKey(candidateHotKey)
            return true
        } catch {
            activeHotKey = hotKeyService.registeredHotKey
            if let activeHotKey {
                preferences.setHotKey(activeHotKey)
            } else if let previousHotKey {
                preferences.setHotKey(previousHotKey)
            }
            presentHotKeyRegistrationError(error)
            return false
        }
    }

    private func activateHotKey(_ candidateHotKey: HotKey) throws {
        try hotKeyService.register(candidateHotKey) { [weak self] in self?.handleAreaHotKey() }
        activeHotKey = hotKeyService.registeredHotKey
        if let activeHotKey {
            preferences.setHotKey(activeHotKey)
            statusMessage = "Хоткей: \(ActiveHotKeyFormatter.symbolic(activeHotKey))"
        }
    }

    var hotKeyDescription: String {
        ActiveHotKeyFormatter.symbolic(activeHotKey)
    }

    var hotKeyReadableDescription: String {
        ActiveHotKeyFormatter.readable(activeHotKey)
    }

    func capture(_ mode: CaptureMode) {
        lastCaptureMode = mode
        lastCaptureWasScrolling = false
        switch mode {
        case .area: captureArea()
        case .window, .fullScreen:
            captureWithSystemUI(mode)
        }
    }

    private func captureArea() {
        lastCaptureMode = .area
        lastCaptureWasScrolling = false
        guard CGPreflightScreenCaptureAccess() else {
            captureWithSystemPicker(.area)
            return
        }
        guard let regionSelectionController else {
            CaptureTelemetry.logger.error("area_capture_unavailable")
            return
        }
        guard let request = prepareCaptureRequest() else {
            statusMessage = "Дождитесь завершения текущего захвата"
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
        activeAreaCaptureTask = captureTask
        activeAreaCaptureID = request.id
        finishCapture(request, task: captureTask, isAreaCapture: true)
    }

    private func captureWithSystemUI(_ mode: CaptureMode) {
        guard CGPreflightScreenCaptureAccess() else {
            captureWithSystemPicker(mode)
            return
        }
        guard let request = prepareCaptureRequest() else { return }
        let captureService = captureService
        let captureTask = Task.detached(priority: .userInitiated) {
            try await captureService.capture(mode, to: request.temporaryURL)
        }
        finishCapture(request, task: captureTask, isAreaCapture: false)
    }

    private func captureWithSystemPicker(_ mode: CaptureMode) {
        guard let regionSelectionController, var request = prepareCaptureRequest() else { return }
        // The system picker may select a different app from the previously frontmost one.
        request.source = nil
        statusMessage = "Выберите источник снимка в системном окне macOS"
        let captureService = captureService
        let captureTask = Task { @MainActor in
            defer { systemContentCapture.endSession() }
            let filter = try await systemContentCapture.select(window: mode == .window)
            if Task.isCancelled { throw CaptureError.cancelled }
            let prepared = try systemContentCapture.prepared(filter)
            let image = try await captureService.capture(prepared)
            if Task.isCancelled { throw CaptureError.cancelled }
            let result: CGImage
            if mode == .area {
                let screen = try systemContentCapture.screen(for: filter)
                let selection = try await regionSelectionController.selectRegion(on: screen, backdropImage: image)
                result = selection.image
            } else {
                result = image
            }
            try await Task.detached(priority: .userInitiated) {
                try captureService.write(result, to: request.temporaryURL)
            }.value
        }
        if mode == .area {
            activeAreaCaptureTask = captureTask
            activeAreaCaptureID = request.id
        }
        finishCapture(request, task: captureTask, isAreaCapture: mode == .area)
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
        task captureTask: Task<Void, Error>,
        isAreaCapture: Bool
    ) {
        Task {
            defer {
                try? FileManager.default.removeItem(at: request.temporaryURL)
                if isAreaCapture, activeAreaCaptureID == request.id {
                    activeAreaCaptureTask = nil
                    activeAreaCaptureID = nil
                    areaHotKeyAttemptCount = 0
                }
            }
            let capturedAt: Date
            do {
                try await captureTask.value
                capturedAt = Date()
                guard beginImport(for: request.id) else { return }
            } catch CaptureError.cancelled {
                let shouldRestart = isAreaCapture && restartAreaCaptureAfterCancellation
                restartAreaCaptureAfterCancellation = false
                cancelCapture(id: request.id)
                resumeShelfAndPresentPendingResults()
                if shouldRestart {
                    areaHotKeyAttemptCount = 1
                    statusMessage = "Повторно открываю выбор области…"
                    captureArea()
                } else {
                    statusMessage = "Захват отменен"
                }
                return
            } catch {
                restartAreaCaptureAfterCancellation = false
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

    private func handleAreaHotKey() {
        guard !captureActivity.canStartCapture else {
            areaHotKeyAttemptCount = 1
            capture(.area)
            return
        }

        guard activeAreaCaptureTask != nil else {
            statusMessage = "Дождитесь завершения текущего захвата"
            return
        }

        areaHotKeyAttemptCount = min(
            areaHotKeyAttemptCount + 1,
            AreaCaptureRecoveryPolicy.forcedRecoveryAttemptCount
        )
        recoverAreaCaptureFromHotKey()
    }

    private func recoverAreaCaptureFromHotKey() {
        switch AreaCaptureRecoveryPolicy.action(
            hasActiveAreaCapture: activeAreaCaptureTask != nil,
            hotKeyAttemptCount: areaHotKeyAttemptCount
        ) {
        case .start:
            areaHotKeyAttemptCount = 1
            capture(.area)
        case .waitForRecovery:
            let attempts = areaHotKeyAttemptCount
            CaptureTelemetry.logger.notice(
                "area_capture_recovery_wait attempts=\(attempts, privacy: .public)"
            )
            statusMessage = "Выбор области не отвечает. Нажмите хоткей еще раз для восстановления"
        case .cancelAndRestart:
            guard !restartAreaCaptureAfterCancellation else {
                CaptureTelemetry.logger.notice("area_capture_restart_already_requested")
                return
            }
            restartAreaCaptureAfterCancellation = true
            let attempts = areaHotKeyAttemptCount
            CaptureTelemetry.logger.notice(
                "area_capture_recovery_triggered attempts=\(attempts, privacy: .public)"
            )
            statusMessage = "Перезапускаю выбор области…"
            activeAreaCaptureTask?.cancel()
            let cancelledVisibleSelection = regionSelectionController?.cancelActiveSelection() ?? false
            CaptureTelemetry.logger.notice(
                "area_capture_restart_requested visible_selection=\(cancelledVisibleSelection, privacy: .public)"
            )
        }
    }

    func startScrollingCapture(forceSystemPicker: Bool = false) {
        lastCaptureWasScrolling = true
        let useSystemPicker = forceSystemPicker || !CGPreflightScreenCaptureAccess()
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
                let selection: RegionSelection
                let preparedCapture: PreparedScrollCapture
                if useSystemPicker {
                    pendingCaptureSource = nil
                    statusMessage = "Выберите прокручиваемое окно в системном диалоге macOS"
                    let filter = try await systemContentCapture.select(window: true)
                    let windowRect = try systemContentCapture.windowRect(for: filter)
                    let image = try await captureService.capture(systemContentCapture.prepared(filter))
                    selection = try await regionSelectionController.selectRegion(captureRect: windowRect, backdropImage: image)
                    preparedCapture = try systemContentCapture.prepared(filter, rect: selection.rect, within: windowRect)
                } else {
                    selection = try await regionSelectionController.selectRegion(using: captureService)
                    preparedCapture = try await captureService.prepareScrollCapture(rect: selection.rect)
                }
                scrollCaptureController?.begin(
                    rect: selection.rect,
                    firstFrame: selection.image,
                    preparedCapture: preparedCapture,
                    model: self
                )
                statusMessage = "Область выбрана. Нажмите «Начать» рядом с рамкой"
            } catch CaptureError.cancelled {
                systemContentCapture.endSession()
                pendingCaptureSource = nil
                pendingScrollCaptureID = nil
                pendingScrollCaptureSequence = nil
                cancelCapture(id: captureID)
                resumeShelfAndPresentPendingResults()
            } catch {
                systemContentCapture.endSession()
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
        systemContentCapture.endSession()
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
        systemContentCapture.endSession()
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
            if preferences.imageFormat == .png {
                try Data(contentsOf: item.imageURL).write(to: destination, options: .atomic)
                statusMessage = "Сохранено: \(destination.lastPathComponent)"
                return
            }
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
            statusMessage = "Удалено"
        } catch { presentDeletionError(error, item: item) }
    }

    func clearHistory() {
        do {
            try history.clearAll()
            selectedItemID = nil
            statusMessage = "История очищена"
        } catch { presentDeletionError(error) }
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

    private func showScreenCapturePermissionAlert() {
        statusMessage = "Нужен доступ к записи экрана"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Выберите источник снимка через macOS"
        alert.informativeText = "macOS не подтвердила общий доступ к экрану для этой копии программы. Можно сделать снимок без переустановки: выберите нужный экран или окно в системном диалоге. Программа получит доступ только к выбранному содержимому на время этого захвата."
        alert.addButton(withTitle: "Выбрать источник")
        alert.addButton(withTitle: "Отмена")
        alert.addButton(withTitle: "Настройки доступа")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if lastCaptureWasScrolling { startScrollingCapture(forceSystemPicker: true) }
            else { captureWithSystemPicker(lastCaptureMode) }
        } else if response == .alertThirdButtonReturn {
            openScreenRecordingSettings()
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func present(_ error: Error) {
        let nsError = error as NSError
        CaptureTelemetry.logger.error("capture_error domain=\(nsError.domain, privacy: .public) code=\(nsError.code) global_access=\(CGPreflightScreenCaptureAccess())")
        if error is ScreenCapturePermissionError ||
            (nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userDeclined.rawValue) {
            guard !isCheckingScreenCapturePermission else { return }
            isCheckingScreenCapturePermission = true
            defer { isCheckingScreenCapturePermission = false }
            showScreenCapturePermissionAlert()
            return
        }
        statusMessage = error.localizedDescription
        let alert = NSAlert(error: error)
        alert.messageText = "Скриншот не готов"
        alert.addButton(withTitle: "ОК")
        alert.addButton(withTitle: "Настройки доступа")
        if alert.runModal() == .alertSecondButtonReturn {
            openScreenRecordingSettings()
        }
    }

    private func presentDeletionError(_ error: Error, item: CaptureItem? = nil) {
        statusMessage = error.localizedDescription
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось удалить скриншот"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "ОК")
        if let item {
            alert.addButton(withTitle: "Показать в Finder")
            if alert.runModal() == .alertSecondButtonReturn {
                reveal(item)
            }
        } else {
            alert.runModal()
        }
    }

    private func presentHotKeyRegistrationError(_ error: Error) {
        statusMessage = error.localizedDescription
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось назначить хоткей"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Выбрать другое сочетание")
        alert.runModal()
    }
}
