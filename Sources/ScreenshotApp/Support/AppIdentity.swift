import Foundation

enum AppIdentity {
    static let displayName = "Богдан Скриншот"

    static var versionDescription: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "локальная сборка"
    }
}
