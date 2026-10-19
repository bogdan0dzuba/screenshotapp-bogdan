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
        precondition(original.collapsedShelfTransparency == 0.73 && original.expandedShelfTransparency == 0.73)
        original.trueLiquidGlass = true
        let reopened = AppPreferences(defaults: defaults)
        precondition(reopened.trueLiquidGlass, "Glass selection must survive relaunch")
        precondition(!reopened.expandedTrueLiquidGlass, "Existing collapsed selection must not enable expanded glass")
        precondition(reopened.collapsedShelfTransparency == 0.73 && reopened.expandedShelfTransparency == 0.73, "Switching glass must preserve transparency")
        reopened.trueLiquidGlass = false
        let restored = AppPreferences(defaults: defaults)
        precondition(!restored.trueLiquidGlass, "Returning to the original appearance must persist")
        precondition(restored.collapsedShelfTransparency == 0.73 && restored.expandedShelfTransparency == 0.73)
        for (collapsed, expanded) in [(false, true), (true, true), (true, false), (false, false)] {
            restored.trueLiquidGlass = collapsed
            restored.expandedTrueLiquidGlass = expanded
            let reloaded = AppPreferences(defaults: defaults)
            precondition(reloaded.trueLiquidGlass == collapsed, "Collapsed selection must persist independently")
            precondition(reloaded.expandedTrueLiquidGlass == expanded, "Expanded selection must persist independently")
            precondition(reloaded.collapsedShelfTransparency == 0.73 && reloaded.expandedShelfTransparency == 0.73)
        }
        restored.collapsedShelfTransparency = 0.12
        restored.expandedShelfTransparency = 0.89
        let independent = AppPreferences(defaults: defaults)
        precondition(independent.collapsedShelfTransparency == 0.12)
        precondition(independent.expandedShelfTransparency == 0.89)
        independent.collapsedShelfTransparency = 2
        precondition(independent.collapsedShelfTransparency == 1)
        precondition(independent.expandedShelfTransparency == 0.89)
        independent.expandedShelfTransparency = -1
        precondition(independent.expandedShelfTransparency == 0)
        independent.collapsedShelfTransparency = .nan
        precondition(independent.collapsedShelfTransparency == AppPreferences.defaultShelfTransparency)
        let normalized = AppPreferences(defaults: defaults)
        precondition(normalized.collapsedShelfTransparency == AppPreferences.defaultShelfTransparency)
        precondition(normalized.expandedShelfTransparency == 0)
        precondition(defaults.double(forKey: "shelfTransparency") == 0.73, "Legacy preference is preserved for rollback")
        print("LiquidGlassPreferencesChecks: OK (legacy migration, independent values, relaunch, bounds, NaN, glass toggles)")
    }
}
