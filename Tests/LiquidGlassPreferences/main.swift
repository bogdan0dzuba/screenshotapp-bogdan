import Foundation
import ScreenshotCore
@testable import ScreenshotApp

@main
struct LiquidGlassPreferencesChecks {
    @MainActor
    static func main() {
        let name = "LiquidGlassPreferencesChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0.12, forKey: "collapsedShelfTransparency")
        defaults.set(0.30, forKey: "expandedShelfTransparency")
        defaults.set(true, forKey: "trueLiquidGlass")
        let migrated = AppPreferences(defaults: defaults)
        precondition(abs(migrated.collapsedShelfTransparency - 0.4) < 0.000001)
        precondition(migrated.expandedShelfTransparency == 1, "Old 30% becomes new 100%")
        let reloaded = AppPreferences(defaults: defaults)
        precondition(reloaded.collapsedShelfTransparency == migrated.collapsedShelfTransparency,
                     "Migration must run only once")
        reloaded.collapsedShelfTransparency = 0.12
        reloaded.expandedShelfTransparency = 0.89
        let independent = AppPreferences(defaults: defaults)
        precondition(independent.collapsedShelfTransparency == 0.12 && independent.expandedShelfTransparency == 0.89)
        independent.collapsedShelfTransparency = 2
        independent.expandedShelfTransparency = -1
        precondition(independent.collapsedShelfTransparency == 1 && independent.expandedShelfTransparency == 0)
        independent.collapsedShelfTransparency = .nan
        precondition(independent.collapsedShelfTransparency == AppPreferences.defaultShelfTransparency)
        precondition(AppPreferences(defaults: defaults).collapsedShelfTransparency == AppPreferences.defaultShelfTransparency)
        for value in [0.0, 0.1, 0.3, 0.5, 0.7, 1.0] {
            let opacity = ShelfAppearancePolicy.backgroundOpacity(value, reduceTransparency: false)
            precondition(opacity >= 0.7 && opacity <= 1, "Glass background must never disappear")
            precondition(ShelfAppearancePolicy.backgroundOpacity(value, reduceTransparency: true) == 1)
        }
        precondition(ShelfAppearancePolicy.backgroundOpacity(1, reduceTransparency: false) == 0.7)
        precondition(ShelfAppearancePolicy.migratedProgress(0.99) == 1)
        precondition(defaults.bool(forKey: "trueLiquidGlass"), "Obsolete settings stay untouched for rollback")
        print("LiquidGlassPreferencesChecks: OK (old 30% -> new 100%, one-time migration, independent values, safe opacity floor, accessibility)")
    }
}
