import AppKit
import ScreenCaptureKit
import ScreenshotCore

/// A picker filter is a grant for the content selected by the person, not global screen access.
/// Keep the picker alive until the one-shot/scrolling operation ends; never cache this grant.
@MainActor
final class SystemContentCaptureController {
    private var observer: PickerObserver?
    private var continuation: CheckedContinuation<SCContentFilter, Error>?
    private var sessionID: UUID?
    private let picker = SCContentSharingPicker.shared

    func select(window: Bool, excludingWindowIDs: [Int] = []) async throws -> SCContentFilter {
        guard sessionID == nil, !Task.isCancelled else { throw CaptureError.cancelled }
        let id = UUID()
        sessionID = id
        let observer = PickerObserver { [weak self] result in
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                let pending = self.continuation
                self.continuation = nil
                pending?.resume(with: result)
            }
        }
        self.observer = observer
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = window ? .singleWindow : .singleDisplay
        configuration.allowsChangingSelectedContent = false
        configuration.excludedWindowIDs = excludingWindowIDs + NSApp.windows.map(\.windowNumber)
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
        picker.defaultConfiguration = configuration
        picker.add(observer)
        picker.isActive = true
        CaptureTelemetry.logger.info("system_content_picker_started")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                picker.present(using: window ? .window : .display)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.sessionID == id else { return }
                self?.endSession()
            }
        }
    }

    func endSession() {
        guard sessionID != nil else { return }
        sessionID = nil
        let pending = continuation
        continuation = nil
        if let observer { picker.remove(observer) }
        observer = nil
        picker.isActive = false
        pending?.resume(throwing: CaptureError.cancelled)
        CaptureTelemetry.logger.info("system_content_picker_ended")
    }

    func screen(for filter: SCContentFilter) throws -> NSScreen {
        if #available(macOS 15.2, *), let display = filter.includedDisplays.first {
            if let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
            }) { return screen }
        }
        // Older macOS exposes content geometry, but not the selected display ID.
        // Never guess between equal-sized monitors: a crop could otherwise target the wrong screen.
        let matches = NSScreen.screens.filter { captureRect(for: $0) == filter.contentRect }
        if matches.count == 1 { return matches[0] }
        if NSScreen.screens.count == 1, let screen = NSScreen.screens.first,
           screen.frame.size == filter.contentRect.size { return screen }
        throw NSError(domain: "ScreenshotApp.SelectedDisplay", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Не удалось сопоставить выбранный экран. Для этого снимка выберите режим «Снимок окна»."
        ])
    }

    func windowRect(for filter: SCContentFilter) throws -> CGRect {
        guard filter.style == .window else { throw CaptureError.missingOutput }
        if #available(macOS 15.2, *), let window = filter.includedWindows.first {
            return window.frame
        }
        guard !filter.contentRect.isEmpty else { throw CaptureError.missingOutput }
        return filter.contentRect
    }

    func prepared(_ filter: SCContentFilter, rect: CGRect? = nil, within contentRect: CGRect? = nil) throws -> PreparedScrollCapture {
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        guard scale.isFinite, scale > 0,
              filter.contentRect.width.isFinite, filter.contentRect.height.isFinite,
              filter.contentRect.width > 0, filter.contentRect.height > 0 else { throw CaptureError.missingOutput }
        if let rect, let contentRect {
            guard let geometry = ScrollCaptureSourceGeometry.resolve(
                captureRect: rect, displayRect: contentRect, pointPixelScale: scale
            ) else { throw CaptureError.missingOutput }
            configuration.sourceRect = geometry.sourceRect
            configuration.width = geometry.pixelWidth
            configuration.height = geometry.pixelHeight
        } else {
            configuration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
            configuration.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        }
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        return PreparedScrollCapture(contentFilter: filter, configuration: configuration, requiresGlobalAccess: false)
    }

    private func captureRect(for screen: NSScreen) -> CGRect {
        ScreenCoordinateTransform.captureRect(fromAppKitRect: screen.frame,
                                              mainScreenTop: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY)
    }
}

private final class PickerObserver: NSObject, SCContentSharingPickerObserver {
    let completion: (Result<SCContentFilter, Error>) -> Void
    init(completion: @escaping (Result<SCContentFilter, Error>) -> Void) { self.completion = completion }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil else { return }
        completion(.failure(CaptureError.cancelled))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil else { return }
        completion(.success(filter))
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        completion(.failure(error))
    }
}
