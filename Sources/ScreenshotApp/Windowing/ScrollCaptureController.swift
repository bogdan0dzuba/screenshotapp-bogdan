import AppKit
import ScreenshotCore
import SwiftUI

@MainActor
final class ScrollCaptureController: ObservableObject {
    @Published private(set) var frameCount = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var isPaused = false
    @Published private(set) var isProcessingFrame = false
    @Published private(set) var hasStarted = false
    @Published private(set) var feedbackState = ScrollCaptureFeedbackState.ready
    @Published private(set) var message = "Область выбрана. Нажмите «Начать», затем прокручивайте небольшими шагами"

    var canStart: Bool {
        isCapturing
            && ScrollCaptureStartPolicy.canStart(
                hasStarted: hasStarted,
                isProcessingFrame: isProcessingFrame
            )
    }

    var canFinish: Bool {
        hasStarted
            && frameCount > 0
            && ScrollCaptureFinishPolicy.canFinish(isCapturing: isCapturing, isFinalizing: isFinalizing)
    }

    private var rect: CGRect = .zero
    private var session = ScrollCaptureSession(frames: [])
    private var selectedFirstFrame: CGImage?
    private var frameSettler = ScrollFrameSettler()
    private var trail = ScrollCaptureTrail()
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var captureTask: Task<Void, Never>?
    private var stitchingTask: Task<Void, Never>?
    private let feedbackOverlay = ScrollCaptureFeedbackOverlay()
    private var isFinalizing = false
    private let maximumFrameCount = 80
    private var targetPixelWidth = 0
    private var targetPixelHeight = 0
    private var lockedDirection: ScrollCaptureDirection?
    private var preparedCapture: PreparedScrollCapture?
    private var captureInFlight = false
    private var captureGeneration = 0

    func begin(
        rect: CGRect,
        firstFrame: CGImage,
        preparedCapture: PreparedScrollCapture,
        model: AppModel
    ) {
        captureTask?.cancel()
        stitchingTask?.cancel()
        self.rect = rect
        self.model = model
        self.preparedCapture = preparedCapture
        targetPixelWidth = firstFrame.width
        targetPixelHeight = firstFrame.height
        selectedFirstFrame = firstFrame
        session = ScrollCaptureSession(frames: [])
        frameSettler.reset()
        trail.reset()
        captureGeneration &+= 1
        frameCount = 0
        isCapturing = true
        isPaused = false
        isProcessingFrame = false
        hasStarted = false
        isFinalizing = false
        lockedDirection = nil
        feedbackState = .ready
        message = "Область выбрана. Нажмите «Начать», затем прокручивайте небольшими шагами"
        showPanel()
        feedbackOverlay.show(for: rect)
        feedbackOverlay.presentSelectionReady()
    }

    func start() {
        guard canStart, let firstFrame = selectedFirstFrame else { return }
        selectedFirstFrame = nil
        hasStarted = true
        session = ScrollCaptureSession(frames: [firstFrame])
        frameSettler.reset()
        frameCount = 1
        feedbackState = .ready
        message = "Первый кадр сохранён ✓ Прокрутите на 1/3 и остановитесь на 0,5 с"
        presentLatestCapturedViewport()
        feedbackOverlay.present(state: .ready, frameCount: frameCount)
        startCaptureLoopIfNeeded()
    }

    func togglePause() {
        guard isCapturing, hasStarted else { return }
        isPaused.toggle()
        if isPaused {
            captureGeneration &+= 1
            frameSettler.reset()
            message = "Пауза. Можно проверить страницу или убрать последний кадр"
            feedbackOverlay.presentPaused(frameCount: frameCount)
        } else {
            feedbackState = .ready
            message = "Прокрутите на 1/3 и остановитесь на 0,5 с до зелёной вспышки"
            feedbackOverlay.present(state: .ready, frameCount: frameCount)
            startCaptureLoopIfNeeded()
        }
    }

    func undoFrame() {
        guard !isFinalizing else { return }
        captureGeneration &+= 1
        isPaused = true
        session.undoLastFrame()
        trail.undoLast()
        frameSettler.reset()
        frameCount = session.frames.count
        if frameCount <= 1 {
            lockedDirection = nil
        }
        presentLatestCapturedViewport()
        message = frameCount == 1
            ? "Пауза. Остался первый кадр - вернитесь к нему перед продолжением"
            : "Пауза. Последний кадр убран - совместите страницу с предыдущим"
        feedbackOverlay.presentPaused(frameCount: frameCount)
    }

    func finish() {
        guard let model, canFinish else {
            return
        }
        isFinalizing = true
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        isPaused = true
        isProcessingFrame = true
        message = "Склеиваю \(frameCount) кадров…"
        feedbackOverlay.presentFinalizing(frameCount: frameCount)
        let frames = session.frames

        stitchingTask = Task { [weak self, weak model] in
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try ScrollStitcher.stitch(frames)
                }.value
                guard !Task.isCancelled, let self, let model else { return }
                isProcessingFrame = false
                isFinalizing = false
                panel?.orderOut(nil)
                panel = nil
                feedbackOverlay.hide()
                releaseCapturedFrames()
                trail.reset()
                self.model = nil
                preparedCapture = nil
                stitchingTask = nil
                model.finishScrolling(with: image)
            } catch {
                guard let self else { return }
                isCapturing = true
                isPaused = true
                isProcessingFrame = false
                isFinalizing = false
                stitchingTask = nil
                message = "Не удалось склеить: \(error.localizedDescription)"
                feedbackOverlay.presentError(message: "Уберите последний кадр и попробуйте снова")
            }
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        stitchingTask?.cancel()
        stitchingTask = nil
        captureGeneration &+= 1
        isCapturing = false
        isPaused = false
        isProcessingFrame = false
        hasStarted = false
        isFinalizing = false
        lockedDirection = nil
        releaseCapturedFrames()
        frameSettler.reset()
        trail.reset()
        panel?.orderOut(nil)
        panel = nil
        feedbackOverlay.hide()
        preparedCapture = nil
        model?.cancelScrolling()
        model = nil
    }

    private func releaseCapturedFrames() {
        session = ScrollCaptureSession(frames: [])
        selectedFirstFrame = nil
        targetPixelWidth = 0
        targetPixelHeight = 0
    }

    private func startCaptureLoopIfNeeded() {
        guard captureTask == nil, isCapturing, hasStarted else { return }
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(360))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                if isPaused { continue }
                await captureAutomaticFrame()
            }
        }
    }

    private func captureAutomaticFrame() async {
        guard !captureInFlight,
              !isPaused,
              isCapturing,
              hasStarted,
              let model,
              let preparedCapture else {
            return
        }
        guard frameCount < maximumFrameCount else {
            isPaused = true
            message = "Достигнут безопасный лимит в \(maximumFrameCount) кадров. Нажмите «Готово»"
            return
        }

        captureInFlight = true
        let generation = captureGeneration
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotScroll-\(UUID().uuidString).png")
        defer {
            captureInFlight = false
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        do {
            try await model.captureService.capture(preparedCapture, to: temporaryURL)
            guard !Task.isCancelled, isCapturing, generation == captureGeneration,
                  let image = NSImage(contentsOf: temporaryURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let previous = session.latestFrame else {
                return
            }
            let targetWidth = targetPixelWidth
            let targetHeight = targetPixelHeight
            let normalizedImage = try await Task.detached(priority: .userInitiated) {
                try ScrollFrameNormalizer.normalized(
                    cgImage,
                    width: targetWidth,
                    height: targetHeight
                )
            }.value
            let settlerSnapshot = frameSettler
            let observedAt = ProcessInfo.processInfo.systemUptime
            let settled = try await Task.detached(priority: .userInitiated) {
                let previousGray = try ScrollStitcher.grayImage(from: previous)
                let nextGray = try ScrollStitcher.grayImage(from: normalizedImage)
                let policy = ScrollFramePolicy(frameHeight: min(previousGray.height, nextGray.height))
                var settler = settlerSnapshot
                let outcome = try settler.observe(
                    accepted: previousGray,
                    observed: nextGray,
                    policy: policy,
                    observedAt: observedAt
                )
                return (settler, outcome)
            }.value
            guard !Task.isCancelled, isCapturing, generation == captureGeneration else { return }
            frameSettler = settled.0
            let outcome = settled.1
            feedbackState = ScrollCaptureFeedbackPolicy.state(for: outcome)

            switch outcome {
            case .unchanged:
                presentLatestCapturedViewport()
                message = "Кадров: \(frameCount). Прокрутите на 1/3 и остановитесь на 0,5 с"
                feedbackOverlay.present(state: feedbackState, frameCount: frameCount)
            case let .pending(decision):
                guard ScrollCaptureDirectionPolicy.accepts(decision, lockedTo: lockedDirection) else {
                    rejectDirectionChange()
                    return
                }
                if let coverage = ScrollCaptureCoveragePolicy.coverage(
                    for: decision,
                    frameHeight: normalizedImage.height
                ) {
                    feedbackOverlay.presentCoverage(coverage)
                }
                message = "Новый участок найден. Не двигайте 0,5 с до зелёной вспышки"
                feedbackOverlay.present(state: feedbackState, frameCount: frameCount)
            case let .commit(decision):
                guard ScrollCaptureDirectionPolicy.accepts(decision, lockedTo: lockedDirection) else {
                    rejectDirectionChange()
                    return
                }
                switch decision {
                case let .append(overlap):
                    session.add(normalizedImage, direction: .down)
                    trail.append(
                        frameHeight: normalizedImage.height,
                        overlap: overlap,
                        captureHeight: rect.height
                    )
                    lockedDirection = .down
                case let .prepend(overlap):
                    session.add(normalizedImage, direction: .up)
                    trail.prepend(
                        frameHeight: normalizedImage.height,
                        overlap: overlap,
                        captureHeight: rect.height
                    )
                    lockedDirection = .up
                case .unchanged, .insufficientOverlap:
                    return
                }
                frameCount = session.frames.count
                presentLatestCapturedViewport()
                message = "Кадр \(frameCount) сохранён ✓ Можно прокручивать дальше"
                feedbackOverlay.present(state: feedbackState, frameCount: frameCount)
            case .insufficientOverlap:
                presentOverlapRecoveryTarget()
                message = "Слишком быстро. Вернитесь немного назад, затем прокрутите меньшим шагом"
                feedbackOverlay.present(state: feedbackState, frameCount: frameCount)
            }
        } catch {
            isPaused = true
            message = "Захват приостановлен: \(error.localizedDescription)"
            feedbackOverlay.presentError(message: "Нажмите «Продолжить», чтобы повторить")
        }
    }

    private func rejectDirectionChange() {
        frameSettler.reset()
        feedbackState = .needsOverlap
        feedbackOverlay.presentNeedsOverlap()
        message = "Не меняйте направление. Вернитесь к последнему кадру и продолжайте в прежнюю сторону"
        feedbackOverlay.present(state: .needsOverlap, frameCount: frameCount)
    }

    private func presentLatestCapturedViewport() {
        guard session.latestFrame != nil else {
            feedbackOverlay.presentSelectionReady()
            return
        }
        feedbackOverlay.presentCapturedViewport(trail: trail)
    }

    private func presentOverlapRecoveryTarget() {
        guard session.latestFrame != nil else {
            feedbackOverlay.presentSelectionReady()
            return
        }
        feedbackOverlay.presentNeedsOverlap()
    }

    private func showPanel() {
        if panel == nil {
            let panel = KeyableScrollCapturePanel(
                contentRect: CGRect(x: 0, y: 0, width: 620, height: 176),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: ScrollCaptureControlsView(controller: self))
            panel.title = "Управление снимком с прокруткой"
            panel.setAccessibilityLabel("Управление снимком с прокруткой")
            panel.onCancel = { [weak self] in self?.cancel() }
            self.panel = panel
        }
        guard let panel,
              let appKitRect = appKitCaptureRect(for: rect),
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKitRect) })
                ?? NSScreen.main else {
            return
        }
        let panelFrame = ScrollCapturePanelPlacement.frame(
            near: appKitRect,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrame(panelFrame, display: false)
        panel.makeKeyAndOrderFront(nil)
    }
}

private func appKitCaptureRect(for captureRect: CGRect) -> CGRect? {
    guard let mainScreenTop = NSScreen.screens.first?.frame.maxY else { return nil }
    return ScreenCoordinateTransform.appKitRect(
        fromCaptureRect: captureRect,
        mainScreenTop: mainScreenTop
    )
}

private final class ScrollCaptureFeedbackOverlay {
    private var borderPanels: [NSPanel] = []
    private var outsideShadePanels: [NSPanel] = []
    private var coveragePanel: NSPanel?
    private var trailOverlay: NSPanel?
    private var coverageView: ScrollCaptureCoverageView?
    private var captureRect: CGRect = .zero
    private var screenRect: CGRect = .zero

    func show(for captureRect: CGRect) {
        hide()
        guard let appKitRect = appKitRect(for: captureRect) else { return }
        let lineWidth: CGFloat = 3
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKitRect) }) ?? NSScreen.main
        let screenBounds = screen?.frame
            ?? NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let outsideRects = [
            CGRect(
                x: screenBounds.minX,
                y: screenBounds.minY,
                width: max(0, appKitRect.minX - screenBounds.minX),
                height: screenBounds.height
            ),
            CGRect(
                x: appKitRect.maxX,
                y: screenBounds.minY,
                width: max(0, screenBounds.maxX - appKitRect.maxX),
                height: screenBounds.height
            ),
            CGRect(
                x: appKitRect.minX,
                y: screenBounds.minY,
                width: appKitRect.width,
                height: max(0, appKitRect.minY - screenBounds.minY)
            ),
            CGRect(
                x: appKitRect.minX,
                y: appKitRect.maxY,
                width: appKitRect.width,
                height: max(0, screenBounds.maxY - appKitRect.maxY)
            ),
        ]
        outsideShadePanels = outsideRects.compactMap { rect in
            guard rect.width > 0, rect.height > 0 else { return nil }
            let panel = overlayPanel(frame: rect)
            let shade = NSView(frame: CGRect(origin: .zero, size: rect.size))
            shade.wantsLayer = true
            shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
            panel.contentView = shade
            panel.orderFrontRegardless()
            return panel
        }

        self.captureRect = appKitRect
        self.screenRect = screenBounds
        let coveragePanel = overlayPanel(frame: screenBounds)
        let coverageView = ScrollCaptureCoverageView(
            frame: CGRect(origin: .zero, size: screenBounds.size)
        )
        coverageView.configure(captureRect: appKitRect, screenRect: screenBounds, trail: .init())
        coveragePanel.contentView = coverageView
        coveragePanel.orderFrontRegardless()
        self.coveragePanel = coveragePanel
        self.trailOverlay = coveragePanel
        self.coverageView = coverageView

        let strips = [
            CGRect(x: appKitRect.minX, y: appKitRect.maxY, width: appKitRect.width, height: lineWidth),
            CGRect(x: appKitRect.minX, y: appKitRect.minY - lineWidth, width: appKitRect.width, height: lineWidth),
            CGRect(x: appKitRect.minX - lineWidth, y: appKitRect.minY, width: lineWidth, height: appKitRect.height),
            CGRect(x: appKitRect.maxX, y: appKitRect.minY, width: lineWidth, height: appKitRect.height),
        ]

        borderPanels = strips.compactMap { strip in
            let visibleStrip = strip.intersection(screenBounds)
            guard !visibleStrip.isNull, !visibleStrip.isEmpty else { return nil }
            let panel = overlayPanel(frame: visibleStrip)
            panel.contentView = ScrollCaptureFeedbackView(frame: CGRect(origin: .zero, size: visibleStrip.size))
            panel.orderFrontRegardless()
            return panel
        }
    }

    func presentCoverage(_ coverage: ScrollCaptureCoverage) {
        coverageView?.present(coverage: coverage)
    }

    func presentSelectionReady() {
        coverageView?.presentSelectionReady()
    }

    func presentCapturedViewport(trail: ScrollCaptureTrail = .init()) {
        coverageView?.configure(captureRect: captureRect, screenRect: screenRect, trail: trail)
        coverageView?.presentCapturedViewport()
    }

    func presentNeedsOverlap() {
        coverageView?.presentNeedsOverlap()
    }

    func present(state: ScrollCaptureFeedbackState, frameCount _: Int) {
        borderViews.forEach { $0.present(state: state) }
    }

    func presentPaused(frameCount _: Int) {
        borderViews.forEach { $0.present(state: .ready) }
    }

    func presentFinalizing(frameCount _: Int) {
        borderViews.forEach { $0.present(state: .aligning) }
    }

    func presentError(message _: String) {
        coverageView?.presentNeedsOverlap()
        borderViews.forEach { $0.present(state: .needsOverlap) }
    }

    func hide() {
        borderPanels.forEach { $0.orderOut(nil) }
        borderPanels.removeAll()
        outsideShadePanels.forEach { $0.orderOut(nil) }
        outsideShadePanels.removeAll()
        coveragePanel?.orderOut(nil)
        coveragePanel = nil
        trailOverlay = nil
        coverageView = nil
    }

    private func appKitRect(for captureRect: CGRect) -> CGRect? {
        appKitCaptureRect(for: captureRect)
    }

    private var borderViews: [ScrollCaptureFeedbackView] {
        borderPanels.compactMap { $0.contentView as? ScrollCaptureFeedbackView }
    }

    private func overlayPanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

}

private final class ScrollCaptureFeedbackView: NSView {
    private var currentState = ScrollCaptureFeedbackState.ready

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemCyan.withAlphaComponent(0.92).cgColor
        layer?.cornerRadius = min(frameRect.width, frameRect.height) / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(state: ScrollCaptureFeedbackState) {
        guard let layer else { return }
        guard state != currentState else { return }
        currentState = state
        let color: NSColor
        switch state {
        case .ready: color = .systemCyan
        case .aligning: color = .systemBlue
        case .acceptedDown, .acceptedUp: color = .systemGreen
        case .needsOverlap: color = .systemOrange
        }
        layer.removeAllAnimations()
        layer.backgroundColor = color.withAlphaComponent(0.95).cgColor
    }
}

private final class KeyableScrollCapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}
