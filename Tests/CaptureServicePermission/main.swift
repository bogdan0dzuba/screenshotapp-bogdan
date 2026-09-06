import CoreGraphics
import Foundation
import ImageIO
import ScreenshotCore
import ScreenCaptureKit

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
        // An explicit picker grant must work even when the global preflight is false.
        // Only the OS image boundary is substituted; PNG writing and error handling stay real.
        let bitmap = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let frame = bitmap.makeImage()!
        let selected = PreparedScrollCapture(contentFilter: SCContentFilter(),
                                             configuration: SCStreamConfiguration(), requiresGlobalAccess: false)
        let selectedService = CaptureService(screenCaptureAccess: { false }, filteredCapture: { _, _ in frame }, selectedCapture: { _, _ in frame })
        var unrestricted = selected
        unrestricted.requiresGlobalAccess = true
        try await denied("unrestricted prepared frame") { try await selectedService.capture(unrestricted, to: output) }
        try await selectedService.capture(selected, to: output)
        guard let decoded = CGImageSourceCreateWithURL(output as CFURL, nil),
              CGImageSourceGetCount(decoded) == 1,
              let image = CGImageSourceCreateImageAtIndex(decoded, 0, nil), image.width == 8, image.height == 6 else {
            throw NSError(domain: "Picker-authorized image was not written", code: 1)
        }
        try sentinel.write(to: output)
        let revokedService = CaptureService(screenCaptureAccess: { false }, selectedCapture: { _, _ in
            throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.userDeclined.rawValue)
        })
        do {
            try await revokedService.capture(selected, to: output)
            throw NSError(domain: "Revoked picker access must fail", code: 1)
        } catch let error as NSError where error.domain == SCStreamErrorDomain { }
        guard try Data(contentsOf: output) == sentinel else {
            throw NSError(domain: "Picker failure must not write output or fall back to legacy capture", code: 1)
        }
        print("CaptureServicePermissionChecks: OK (global denial, picker grant, picker revocation, output integrity)")
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
