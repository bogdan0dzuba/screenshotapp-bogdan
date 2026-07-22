import Foundation

public enum AutomaticUpdateDefaultsMigration {
    private static let markerKey = "ScreenshotApp.didEnableSeamlessAutomaticUpdatesV1"

    public static func shouldEnableAutomaticUpdates(in defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: markerKey) else { return false }
        defaults.set(true, forKey: markerKey)
        return true
    }
}
