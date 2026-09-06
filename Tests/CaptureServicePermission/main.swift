import CoreGraphics
import Foundation
import ScreenshotCore

@main
struct CaptureServicePermissionChecks {
    @MainActor
    static func main() async throws {
        let service = CaptureService(screenCaptureAccess: { false })
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("DeniedCapture-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: output) }
        // An existing file must not be removed by a denied request either.
        let sentinel = Data("untouched".utf8)
        try sentinel.write(to: output)
        let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
        try await denied("frozen selection") { _ = try await service.captureFrozenScreen(rect: rect) }
        for mode in [CaptureMode.area, .window, .fullScreen] {
            try await denied("system capture") { try await service.capture(mode, to: output) }
        }
        try await denied("native region") { try await service.capture(rect: rect, to: output) }
        try await denied("scroll preparation") { _ = try await service.prepareScrollCapture(rect: rect) }
        guard try Data(contentsOf: output) == sentinel else {
            throw NSError(domain: "Denied capture modified output", code: 1)
        }
        print("CaptureServicePermissionChecks: OK (6 denied capture paths, output untouched)")
    }

    @MainActor
    static func denied(_ name: String, operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch ScreenCapturePermissionError.denied {
            return
        }
        throw NSError(domain: "Missing access must block \(name)", code: 1)
    }
}
