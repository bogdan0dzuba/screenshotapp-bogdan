import AppKit
import CoreGraphics
import ScreenshotCore

enum CaptureSourceProvider {
    static func current() -> CaptureSource? {
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let windows = visibleWindows()

        if let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != ownProcessID,
           let source = source(for: application, windows: windows) {
            if source.isComputerUseControlWindow {
                return fallbackSource(
                    excludingProcessIDs: [ownProcessID, application.processIdentifier],
                    windows: windows
                ) ?? source.withoutWindowTitle
            }
            return source
        }

        return fallbackSource(excludingProcessIDs: [ownProcessID], windows: windows)
    }

    private static func source(
        for application: NSRunningApplication,
        windows: [[String: Any]]
    ) -> CaptureSource? {
        let processID = application.processIdentifier
        let applicationName = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? windows.first(where: { self.processID(in: $0) == processID })?[kCGWindowOwnerName as String] as? String
        guard let applicationName, !applicationName.isEmpty else { return nil }

        let windowTitle = windows.first(where: {
            self.processID(in: $0) == processID && layer(in: $0) == 0
        })?[kCGWindowName as String] as? String
        return CaptureSource(applicationName: applicationName, windowTitle: windowTitle)
    }

    private static func visibleWindows() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func fallbackSource(
        excludingProcessIDs: Set<pid_t>,
        windows: [[String: Any]]
    ) -> CaptureSource? {
        for window in windows where layer(in: window) == 0 {
            guard let processID = processID(in: window),
                  !excludingProcessIDs.contains(processID),
                  let application = NSRunningApplication(processIdentifier: processID),
                  let source = source(for: application, windows: windows),
                  !source.isComputerUseControlWindow else { continue }
            return source
        }
        return nil
    }

    private static func processID(in window: [String: Any]) -> pid_t? {
        (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    }

    private static func layer(in window: [String: Any]) -> Int {
        (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? .max
    }
}
