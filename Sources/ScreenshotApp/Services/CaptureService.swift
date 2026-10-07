import AppKit
import Foundation
import ImageIO
import ScreenCaptureKit
import ScreenshotCore
import UniformTypeIdentifiers

enum CaptureMode {
    case area
    case window
    case fullScreen
}

enum CaptureError: LocalizedError, Equatable {
    case cancelled
    case failed(Int32)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .cancelled: "Захват отменен"
        case let .failed(code): "Не удалось сделать снимок (код \(code))"
        case .missingOutput: "Снимок не был создан"
        }
    }
}

struct PreparedScrollCapture: @unchecked Sendable {
    let contentFilter: SCContentFilter
    let configuration: SCStreamConfiguration
    // Picker filters carry a separate, user-selected session grant.
    var requiresGlobalAccess = true
}

struct CaptureService: Sendable {
    var screenCaptureAccess: @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }
    var filteredCapture: @Sendable (SCContentFilter, SCStreamConfiguration) async throws -> CGImage = { filter, configuration in
        try await AsyncDeadline.value(timeout: 8) { completion in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image { completion(.success(image)) }
                else { completion(.failure(error ?? CaptureError.missingOutput)) }
            }
        }
    }

    var selectedCapture: @Sendable (SCContentFilter, SCStreamConfiguration) async throws -> CGImage = {
        try await SelectedContentFrameCapture.image(filter: $0, configuration: $1)
    }

    @MainActor
    func captureSelectedRegion(rect: CGRect) async throws -> CGImage {
        try Task.checkCancellation()
        let prepared = try await prepareScrollCapture(rect: rect.integral)
        try Task.checkCancellation()
        let image = try await capture(prepared)
        try Task.checkCancellation()
        CaptureTelemetry.logger.notice("live_region_captured width=\(image.width, privacy: .public) height=\(image.height, privacy: .public)")
        return image
    }

    func captureFrozenScreen(rect: CGRect) async throws -> CGImage {
        try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        let integral = rect.integral
        if #available(macOS 15.2, *) {
            do {
                let image = try await AsyncDeadline.value(timeout: 0.5) { completion in
                    SCScreenshotManager.captureImage(in: integral) { image, error in
                        if let image {
                            completion(.success(image))
                        } else {
                            completion(.failure(error ?? CaptureError.missingOutput))
                        }
                    }
                }
                try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
                CaptureTelemetry.logger.notice("frozen_screen_captured")
                return image
            } catch is CancellationError {
                throw CaptureError.cancelled
            } catch {
                CaptureTelemetry.logger.notice("frozen_screen_native_fallback")
                return try await captureFrozenScreenFallback(rect: integral)
            }
        }

        return try await captureFrozenScreenFallback(rect: integral)
    }

    private func captureFrozenScreenFallback(rect: CGRect) async throws -> CGImage {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotApp-Frozen-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        try await runScreencapture(arguments: ["-x", "-R", region, temporaryURL.path], outputURL: temporaryURL)
        guard let source = CGImageSourceCreateWithURL(temporaryURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureError.missingOutput
        }
        CaptureTelemetry.logger.notice("frozen_screen_captured_fallback")
        return image
    }

    func write(_ image: CGImage, to outputURL: URL) throws {
        try Self.writePNG(image, to: outputURL)
    }

    func capture(_ mode: CaptureMode, to outputURL: URL) async throws {
        try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        var arguments = ["-x"]
        switch mode {
        case .area: arguments += ["-i", "-s"]
        case .window: arguments += ["-i", "-w"]
        case .fullScreen: break
        }
        arguments.append(outputURL.path)
        try await runScreencapture(arguments: arguments, outputURL: outputURL)
    }

    func capture(rect: CGRect, to outputURL: URL) async throws {
        try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        let integral = rect.integral
        if #available(macOS 15.2, *) {
            do {
                try? FileManager.default.removeItem(at: outputURL)
                let image = try await AsyncDeadline.value(timeout: 8) { completion in
                    SCScreenshotManager.captureImage(in: integral) { image, error in
                        if let image { completion(.success(image)) }
                        else { completion(.failure(error ?? CaptureError.missingOutput)) }
                    }
                }
                try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
                try Self.writePNG(image, to: outputURL)
                CaptureTelemetry.logger.info("native_region_capture_finished")
                return
            } catch is CancellationError {
                throw CaptureError.cancelled
            } catch {
                CaptureTelemetry.logger.notice("native_region_capture_fallback")
            }
        }
        let region = "\(Int(integral.minX)),\(Int(integral.minY)),\(Int(integral.width)),\(Int(integral.height))"
        try await runScreencapture(arguments: ["-x", "-R", region, outputURL.path], outputURL: outputURL)
    }

    @MainActor
    func prepareScrollCapture(rect: CGRect) async throws -> PreparedScrollCapture {
        try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        guard let mainScreenTop = NSScreen.screens.first?.frame.maxY else {
            throw CaptureError.missingOutput
        }
        let appKitRect = ScreenCoordinateTransform.appKitRect(
            fromCaptureRect: rect,
            mainScreenTop: mainScreenTop
        )
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitRect) }),
              let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? CGDirectDisplayID else {
            throw CaptureError.missingOutput
        }

        let shareableContent: SCShareableContent = try await AsyncDeadline.value(timeout: 8) { completion in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
                if let content { completion(.success(content)) }
                else { completion(.failure(error ?? CaptureError.missingOutput)) }
            }
        }
        try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.missingOutput
        }
        let currentPID = NSRunningApplication.current.processIdentifier
        let excludedApplications = shareableContent.applications.filter {
            $0.processID == currentPID
        }
        // After a live selection closes, this app may have no shareable windows.
        // An empty exclusion list then correctly captures the remaining desktop.
        let contentFilter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let displayCaptureRect = ScreenCoordinateTransform.captureRect(
            fromAppKitRect: screen.frame,
            mainScreenTop: mainScreenTop
        )
        guard let geometry = ScrollCaptureSourceGeometry.resolve(
            captureRect: rect,
            displayRect: displayCaptureRect,
            pointPixelScale: CGFloat(contentFilter.pointPixelScale)
        ) else {
            throw CaptureError.missingOutput
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect
        configuration.width = geometry.pixelWidth
        configuration.height = geometry.pixelHeight
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        return PreparedScrollCapture(
            contentFilter: contentFilter,
            configuration: configuration
        )
    }

    func capture(_ prepared: PreparedScrollCapture) async throws -> CGImage {
        if prepared.requiresGlobalAccess {
            try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        }
        // The OS enforces the picker filter's per-session grant. A global preflight cannot
        // validate it, and no legacy fallback may replace the explicitly selected content.
        let image = try await (prepared.requiresGlobalAccess ? filteredCapture : selectedCapture)(
            prepared.contentFilter, prepared.configuration
        )
        if prepared.requiresGlobalAccess {
            try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        }
        CaptureTelemetry.logger.info("filtered_scroll_region_capture_finished")
        return image
    }

    func capture(_ prepared: PreparedScrollCapture, to outputURL: URL) async throws {
        let image = try await capture(prepared)
        try Self.writePNG(image, to: outputURL)
    }

    private static func writePNG(_ image: CGImage, to outputURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.missingOutput
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.missingOutput
        }
    }

    private func runScreencapture(arguments: [String], outputURL: URL) async throws {
        try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        try? FileManager.default.removeItem(at: outputURL)
        let status = try await CaptureProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/screencapture"),
            arguments: arguments,
            outputURL: outputURL,
            // Interactive capture waits for the person; only preparation has a deadline.
            timeout: arguments.contains("-i") ? nil : 8
        )
        CaptureTelemetry.logger.info("capture_process_finished status=\(status)")
        switch CaptureProcessOutcome.resolve(terminationStatus: status,
                                            outputExists: FileManager.default.fileExists(atPath: outputURL.path)) {
        case .success: break
        case .cancelled: throw CaptureError.cancelled
        case let .failed(code): throw CaptureError.failed(code)
        }
        do {
            try ScreenCapturePermission.requireAccess(preflight: screenCaptureAccess)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
