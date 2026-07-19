import Foundation

enum AppIdentity {
    static let displayName = "Богдан Скриншот"

    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)) where !build.isEmpty:
            return "\(version) (\(build))"
        case let (.some(version), _):
            return version
        default:
            return "локальная сборка"
        }
    }
}
