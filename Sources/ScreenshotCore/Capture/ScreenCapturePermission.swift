import CoreGraphics
import Foundation

public enum ScreenCapturePermissionError: LocalizedError {
    case denied

    public var errorDescription: String? {
        "Для снимков других приложений нужен доступ «Запись экрана». Без него macOS может показывать только обои и окна самого скриншотера. Откройте настройки доступа, включите «Богдан Скриншот» в разделе «Запись экрана и системного звука», затем полностью завершите и снова откройте установленное приложение."
    }
}

public struct ScreenCapturePermission {
    private var didRequestAccess = false
    public init() {}

    public mutating func requestIfNeeded(preflight: () -> Bool, request: () -> Bool) -> Bool {
        if preflight() { return true }
        if !didRequestAccess {
            didRequestAccess = true
            _ = request()
        }
        // A successful request may still require restarting the application.
        return preflight()
    }

    public static func requireAccess(preflight: () -> Bool = { CGPreflightScreenCaptureAccess() }) throws {
        guard preflight() else { throw ScreenCapturePermissionError.denied }
    }
}
