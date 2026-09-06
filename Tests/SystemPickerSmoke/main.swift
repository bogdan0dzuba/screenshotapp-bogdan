import AppKit
import Foundation
import ScreenCaptureKit
import ScreenshotCore
import Vision

/// Manual integration harness: two independent app bundles, no TCC reset or global grant.
/// Select only the synthetic fixture window. No captured pixels are saved.
@MainActor
final class SmokeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let controller = SystemContentCaptureController()
    let resultURL = URL(fileURLWithPath: CommandLine.arguments.last!)
    let fixture = CommandLine.arguments.contains("--fixture")
    var status: NSTextField!
    var checking = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: CGRect(x: 100, y: 200, width: 620, height: 260),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        if fixture, let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.frame.maxX - 660, y: screen.frame.minY + 200))
        }
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.title = fixture ? "External fixture 5.52" : "Picker verification 5.52"
        let label = NSTextField(labelWithString: fixture ? "SCREENSHOT 5.52 TEST\nExternal synthetic window" : "Choose only External fixture 5.52")
        label.font = .systemFont(ofSize: 28)
        label.frame = CGRect(x: 25, y: 140, width: 570, height: 100)
        window.contentView?.addSubview(label)
        if !fixture {
            let button = NSButton(title: "Verify window capture", target: self, action: #selector(verify))
            button.frame = CGRect(x: 25, y: 90, width: 240, height: 35)
            window.contentView?.addSubview(button)
            status = NSTextField(labelWithString: "Global access: \(CGPreflightScreenCaptureAccess())")
            status.frame = CGRect(x: 25, y: 20, width: 570, height: 60)
            window.contentView?.addSubview(status)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if fixture {
            let data = try! JSONSerialization.data(withJSONObject: ["windowID": window.windowNumber])
            try! data.write(to: resultURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func verify() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            let before = CGPreflightScreenCaptureAccess()
            var report: [String: Any] = ["globalAccessBefore": before]
            defer {
                controller.endSession()
                report["globalAccessAfter"] = CGPreflightScreenCaptureAccess()
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: resultURL)
                }
            }
            do {
                let fixtureURL = resultURL.deletingLastPathComponent().appendingPathComponent("fixture.json")
                let fixtureInfo = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Int]
                let fixtureID = fixtureInfo["windowID"]!
                let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                let exclusions = windows.compactMap { $0[kCGWindowNumber as String] as? Int }.filter { $0 != fixtureID }
                let filter = try await controller.select(window: true, excludingWindowIDs: exclusions)
                if #available(macOS 15.2, *) {
                    report["selectedWindowCount"] = filter.includedWindows.count
                    report["selectedExternalWindow"] = filter.includedWindows.count == 1 &&
                        filter.includedWindows.first?.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
                }
                let prepared = try controller.prepared(filter)
                let service = CaptureService()
                var image = try await service.capture(prepared)
                // Reuse the same picker filter, as scrolling capture does, without widening access.
                for _ in 0..<2 { image = try await service.capture(prepared) }
                report["framesCaptured"] = 3
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: image).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                let matches = text.contains("SCREENSHOT 5.52 TEST") && text.contains("External synthetic window")
                report["fixtureTextMatched"] = matches
                report["width"] = image.width
                report["height"] = image.height
                report["passed"] = !before && matches
                status.stringValue = (!before && matches) ? "PASS: external window, global access remains false" : "FAIL: see report"
            } catch CaptureError.cancelled {
                report["cancelled"] = true
                status.stringValue = "Cancelled; no image saved"
            } catch {
                report["errorDomain"] = (error as NSError).domain
                report["errorCode"] = (error as NSError).code
                status.stringValue = "FAIL: \(error.localizedDescription)"
            }
        }
    }
}

@main
struct Smoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = SmokeDelegate()
        app.delegate = delegate
        app.run()
    }
}
