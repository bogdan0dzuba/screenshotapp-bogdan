import CoreGraphics
import Foundation

public struct ShelfWindowSizeStore {
    private let defaults: UserDefaults
    private let widthKey: String
    private let heightKey: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "shelf.expanded") {
        self.defaults = defaults
        widthKey = "\(keyPrefix).width"
        heightKey = "\(keyPrefix).height"
    }

    public func load(default defaultSize: CGSize = ShelfMetrics.expandedSize) -> CGSize {
        let width = defaults.double(forKey: widthKey)
        let height = defaults.double(forKey: heightKey)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return defaultSize }
        return CGSize(width: width, height: height)
    }

    public func save(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        defaults.set(size.width, forKey: widthKey)
        defaults.set(size.height, forKey: heightKey)
    }
}
