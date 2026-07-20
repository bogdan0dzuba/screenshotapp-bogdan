import OSLog

enum CaptureTelemetry {
    static let logger = Logger(
        subsystem: "local.codex.ScreenshotApp",
        category: "CaptureLatency"
    )
}
