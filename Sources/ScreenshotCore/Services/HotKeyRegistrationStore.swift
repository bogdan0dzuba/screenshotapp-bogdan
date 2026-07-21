public struct HotKeyRegistrationStore<Handle> {
    public private(set) var hotKey: HotKey?
    public private(set) var handle: Handle?

    public init() {}

    public mutating func replace(
        with candidate: HotKey,
        register: () throws -> Handle,
        unregister: (Handle) -> Void
    ) rethrows {
        if hotKey == candidate, handle != nil {
            return
        }

        let candidateHandle = try register()
        let previousHandle = handle
        hotKey = candidate
        handle = candidateHandle

        if let previousHandle {
            unregister(previousHandle)
        }
    }

    public mutating func unregisterCurrent(using unregister: (Handle) -> Void) {
        if let handle {
            unregister(handle)
        }
        hotKey = nil
        handle = nil
    }
}
