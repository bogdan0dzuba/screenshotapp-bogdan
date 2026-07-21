import AppKit
import ScreenshotCore
import SwiftUI

@MainActor
final class ScrollCaptureController: ObservableObject {
    @Published private(set) var frameCount = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var isPaused = false
    @Published private(set) var isProcessingFrame = false
    @Published private(set) var message = "Прокручивайте вверх или вниз - кадры добавляются автоматически"

    private var rect: CGRect = .zero
    private var session = ScrollCaptureSession(frames: [])
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var captureTask: Task<Void, Never>?
    private var stitchingTask: Task<Void, Never>?
    private let maximumFrameCount = 80

    func begin(rect: CGRect, firstFrame: CGImage, model: AppModel) {
        captureTask?.cancel()
        stitchingTask?.cancel()
        self.rect = rect
        self.model = model
        session = ScrollCaptureSession(frames: [firstFrame])
        frameCount = 1
        isCapturing = true
        isPaused = false
        isProcessingFrame = false
        message = "Прокручивайте вверх или вниз - кадры добавляются автоматически"
        showPanel()
        startCaptureLoopIfNeeded()
    }

    func togglePause() {
        guard isCapturing else { return }
        isPaused.toggle()
        if isPaused {
            message = "Пауза. Можно проверить страницу или убрать последний кадр"
        } else {
            message = "Прокручивайте вверх или вниз - кадры добавляются автоматически"
            startCaptureLoopIfNeeded()
        }
    }

    func undoFrame() {
        guard !isProcessingFrame else { return }
        isPaused = true
        session.undoLastFrame()
        frameCount = session.frames.count
        message = frameCount == 1 ? "Пауза. Остался первый кадр" : "Пауза. Последний кадр убран"
    }

    func finish() {
        guard let model, isCapturing, !isProcessingFrame else { return }
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        isPaused = true
        isProcessingFrame = true
        message = "Склеиваю \(frameCount) кадров…"
        let frames = session.frames

        stitchingTask = Task { [weak self, weak model] in
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try ScrollStitcher.stitch(frames)
                }.value
                guard !Task.isCancelled, let self, let model else { return }
                isProcessingFrame = false
                panel?.orderOut(nil)
                panel = nil
                self.model = nil
                stitchingTask = nil
                model.finishScrolling(with: image)
            } catch {
                guard let self else { return }
                isCapturing = true
                isPaused = true
                isProcessingFrame = false
                stitchingTask = nil
                message = "Не удалось склеить: \(error.localizedDescription)"
            }
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        stitchingTask?.cancel()
        stitchingTask = nil
        isCapturing = false
        isPaused = false
        isProcessingFrame = false
        panel?.orderOut(nil)
        panel = nil
        model?.cancelScrolling()
        model = nil
    }

    private func startCaptureLoopIfNeeded() {
        guard captureTask == nil, isCapturing else { return }
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
        guard !isProcessingFrame, !isPaused, isCapturing, let model else { return }
        guard frameCount < maximumFrameCount else {
            isPaused = true
            message = "Достигнут безопасный лимит в \(maximumFrameCount) кадров. Нажмите «Готово»"
            return
        }

        isProcessingFrame = true
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotScroll-\(UUID().uuidString).png")
        defer {
            isProcessingFrame = false
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        do {
            try await model.captureService.capture(rect: rect, to: temporaryURL)
            guard !Task.isCancelled, isCapturing,
                  let image = NSImage(contentsOf: temporaryURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let previous = session.latestFrame else {
                return
            }
            let decision = try await Task.detached(priority: .userInitiated) {
                let previousGray = try ScrollStitcher.grayImage(from: previous)
                let nextGray = try ScrollStitcher.grayImage(from: cgImage)
                let policy = ScrollFramePolicy(frameHeight: min(previousGray.height, nextGray.height))
                return try ScrollFrameClassifier.decision(
                    previous: previousGray,
                    next: nextGray,
                    policy: policy
                )
            }.value
            guard !Task.isCancelled, isCapturing else { return }

            switch decision {
            case .unchanged:
                message = "Прокручивайте вверх или вниз - кадры добавляются автоматически"
            case .append:
                session.add(cgImage, direction: .down)
                frameCount = session.frames.count
                message = "Кадр \(frameCount) добавлен снизу. Продолжайте или нажмите «Готово»"
            case .prepend:
                session.add(cgImage, direction: .up)
                frameCount = session.frames.count
                message = "Кадр \(frameCount) добавлен сверху. Продолжайте или нажмите «Готово»"
            case .insufficientOverlap:
                message = "Слишком большой скачок. Прокрутите немного вверх, чтобы вернуть перекрытие"
            }
        } catch {
            isPaused = true
            message = "Захват приостановлен: \(error.localizedDescription)"
        }
    }

    private func showPanel() {
        if panel == nil {
            let panel = KeyableScrollCapturePanel(
                contentRect: CGRect(x: 0, y: 0, width: 530, height: 128),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: ScrollCaptureControlsView(controller: self))
            panel.onCancel = { [weak self] in self?.cancel() }
            self.panel = panel
        }
        let mouseLocation = NSEvent.mouseLocation
        guard let panel,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 24))
        panel.makeKeyAndOrderFront(nil)
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
