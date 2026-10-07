import Foundation

enum AppIdentity {
    static let displayName = "Скриншутер"

    static var versionDescription: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "локальная сборка"
    }
}
