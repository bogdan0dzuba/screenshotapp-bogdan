import Foundation
import ScreenshotCore

func checkScreenCapturePermission() throws {
    do {
        try ScreenCapturePermission.requireAccess(preflight: { false })
        throw NSError(domain: "Unrestricted capture must reject missing global permission", code: 1)
    } catch ScreenCapturePermissionError.denied { }
    try ScreenCapturePermission.requireAccess(preflight: { true })
}
