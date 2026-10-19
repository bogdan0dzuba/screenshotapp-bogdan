import Foundation
@testable import ScreenshotApp

@main
struct LiquidGlassPreferencesChecks {
    @MainActor
    static func main() {
        let name = "LiquidGlassPreferencesChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0.73, forKey: "shelfTransparency")
        let original = AppPreferences(defaults: defaults)
        precondition(!original.trueLiquidGlass, "Existing installations must keep their appearance")
        precondition(!original.expandedTrueLiquidGlass, "Expanded glass must be opt-in")
        precondition(original.shelfTransparency == 0.73)
        original.trueLiquidGlass = true
        let reopened = AppPreferences(defaults: defaults)
        precondition(reopened.trueLiquidGlass, "Glass selection must survive relaunch")
        precondition(!reopened.expandedTrueLiquidGlass, "Existing collapsed selection must not enable expanded glass")
        precondition(reopened.shelfTransparency == 0.73, "Switching glass must preserve transparency")
        reopened.trueLiquidGlass = false
        let restored = AppPreferences(defaults: defaults)
        precondition(!restored.trueLiquidGlass, "Returning to the original appearance must persist")
        precondition(restored.shelfTransparency == 0.73)
        for (collapsed, expanded) in [(false, true), (true, true), (true, false), (false, false)] {
            restored.trueLiquidGlass = collapsed
            restored.expandedTrueLiquidGlass = expanded
            let reloaded = AppPreferences(defaults: defaults)
            precondition(reloaded.trueLiquidGlass == collapsed, "Collapsed selection must persist independently")
            precondition(reloaded.expandedTrueLiquidGlass == expanded, "Expanded selection must persist independently")
            precondition(reloaded.shelfTransparency == 0.73)
        }
        print("LiquidGlassPreferencesChecks: OK")
    }
}
