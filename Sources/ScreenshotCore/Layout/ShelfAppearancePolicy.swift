import Foundation

public enum ShelfAppearancePolicy {
    public static let maximumBackgroundTransparency = 0.30

    public static func progress(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }

    public static func migratedProgress(_ legacy: Double) -> Double {
        progress(legacy / maximumBackgroundTransparency)
    }

    public static func backgroundOpacity(_ value: Double, reduceTransparency: Bool) -> Double {
        reduceTransparency ? 1 : 1 - maximumBackgroundTransparency * progress(value)
    }
}
