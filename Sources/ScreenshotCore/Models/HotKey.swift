import Foundation

public struct HotKeyModifiers: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = HotKeyModifiers(rawValue: 1 << 0)
    public static let shift = HotKeyModifiers(rawValue: 1 << 1)
    public static let option = HotKeyModifiers(rawValue: 1 << 2)
    public static let control = HotKeyModifiers(rawValue: 1 << 3)
}

public struct HotKey: Codable, Equatable, Sendable {
    public var key: String
    public var keyCode: UInt32
    public var modifiers: HotKeyModifiers

    public init(key: String, keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.key = key.uppercased()
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultCapture = HotKey(
        key: "A",
        keyCode: 0,
        modifiers: [.command, .shift]
    )
}
