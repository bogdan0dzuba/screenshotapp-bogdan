import AppKit
import Foundation
import ScreenshotCore

enum PasteboardService {
    @MainActor
    static func copyImage(at url: URL) throws {
        try ScreenshotTransfer.writeImage(at: url, to: .general)
    }

    @MainActor
    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
