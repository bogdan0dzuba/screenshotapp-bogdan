import AppKit

@MainActor
final class CaptureFeedbackPanel {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var presentationCount = 0
    private var isRetryingFrame = false

    func show(_ message: String, duration: Duration = .seconds(5)) {
        guard !isRetryingFrame else { return }
        hide()
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        let inset: CGFloat = 16
        let width = min(360, visible.width - 2 * inset)
        guard width > 2 * inset, visible.height > 4 * inset else { return }

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 4
        let textBounds = CGRect(x: 0, y: 0, width: width - 2 * inset, height: visible.height)
        let textHeight = label.cell?.cellSize(forBounds: textBounds).height ?? label.fittingSize.height
        let height = min(ceil(textHeight) + 2 * inset, visible.height - 2 * inset)
        let frame = CGRect(x: visible.maxX - width - inset, y: visible.maxY - height - inset,
                           width: width, height: height)
        let panel = FeedbackWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.title = "Статус Скриншутера"
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        label.frame = background.bounds.insetBy(dx: inset, dy: inset)
        background.addSubview(label)
        panel.contentView = background
        self.panel = panel
        panel.orderFrontRegardless()
        presentationCount += 1

        dismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func captureFrame<Frame>(_ capture: () async throws -> Frame) async throws -> Frame {
        hide()
        let previousPresentationCount = presentationCount
        let frame = try await capture()
        guard presentationCount != previousPresentationCount else { return frame }

        // A recovery message can appear while the compositor is preparing the first frame.
        hide()
        try Task.checkCancellation()
        isRetryingFrame = true
        defer { isRetryingFrame = false }
        return try await capture()
    }
}

private final class FeedbackWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
