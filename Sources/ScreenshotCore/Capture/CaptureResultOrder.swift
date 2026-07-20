public enum CaptureResultOrder {
    public static func sequenceToPresent(
        pending: [UInt64],
        latestPresented: UInt64
    ) -> UInt64? {
        pending.max().flatMap { $0 > latestPresented ? $0 : nil }
    }
}
