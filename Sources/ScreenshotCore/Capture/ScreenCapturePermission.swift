import CoreGraphics
import Foundation

public enum ScreenCapturePermissionError: LocalizedError {
    case denied

    public var errorDescription: String? {
        "macOS не подтвердила общий доступ к экрану. Выберите источник снимка через системный диалог macOS или проверьте разрешение «Запись экрана» для установленной копии приложения."
    }
}

public enum ScreenCapturePermission {
    public static func requireAccess(preflight: () -> Bool = { CGPreflightScreenCaptureAccess() }) throws {
        guard preflight() else { throw ScreenCapturePermissionError.denied }
    }
}
