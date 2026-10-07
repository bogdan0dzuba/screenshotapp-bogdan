import AppKit
import Carbon
import ScreenshotCore

@main
struct HotKeyRegistrationChecks {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        try require(GlobalHotKeyService.deliveryDelayMilliseconds(eventTime: 17, now: 20) == 3000,
                    "delivery timing must expose an event queued for three seconds")
        try require(GlobalHotKeyService.deliveryDelayMilliseconds(eventTime: 20, now: 19) == -1,
                    "invalid event timing must not masquerade as zero latency")
        let service = GlobalHotKeyService()
        var count = 0
        let first = HotKey(key: "F20", keyCode: 90, modifiers: [.command, .control, .option, .shift])
        let second = HotKey(key: "F19", keyCode: 80, modifiers: [.command, .control, .option, .shift])
        try service.register(first) { count += 1 }
        try dispatch(id: 1)
        try require(count == 1, "registered event must reach action")
        try service.register(first) { count += 2 }
        try dispatch(id: 1)
        try require(count == 3, "same-key registration must preserve ID and update action")
        try service.register(second) { count += 4 }
        try dispatch(id: 1)
        try require(count == 3, "stale event must not capture")
        try dispatch(id: 2, signature: 0)
        try require(count == 3, "foreign signature must not capture")
        try dispatch(id: 2)
        try require(count == 7, "replacement event must reach action")
        do {
            try service.register(HotKey(key: "A", keyCode: 0, modifiers: [])) { count = -1 }
            throw NSError(domain: "missing modifier was accepted", code: 1)
        } catch GlobalHotKeyService.RegistrationError.missingModifier { }
        try dispatch(id: 2)
        try require(count == 11, "failed replacement must preserve working action")
        let escapeService = GlobalHotKeyService(signature: 0x53484553, allowsUnmodifiedEscape: true)
        var escapeCount = 0
        let escape = HotKey(key: "ESC", keyCode: 53, modifiers: [])
        try escapeService.register(escape) { escapeCount += 1 }
        try dispatch(id: 1, signature: 0x53484553)
        try require(count == 11 && escapeCount == 1, "Escape must not trigger the capture binding")
        try dispatch(id: 2)
        try require(count == 15 && escapeCount == 1, "capture must not trigger Escape")
        escapeService.unregister()
        try dispatch(id: 1, signature: 0x53484553)
        try require(escapeCount == 1, "unregistered Escape must stop receiving events")
        try escapeService.register(escape) { escapeCount += 1 }
        try dispatch(id: 1, signature: 0x53484553)
        try require(escapeCount == 1, "old Escape event must not cancel a newer selection")
        try dispatch(id: 2, signature: 0x53484553)
        try require(escapeCount == 2, "new Escape binding must remain active")
        escapeService.unregister()
        print("HotKeyRegistrationChecks: OK (Carbon dispatch, replacement, stale/foreign events, isolated temporary Escape)")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func dispatch(id: UInt32, signature: OSType = 0x53485346) throws {
        var event: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                  GetCurrentEventTime(), EventAttributes(kEventAttributeNone), &event)
        guard created == noErr, let event else { throw NSError(domain: "CreateEvent", code: Int(created)) }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: signature, id: id)
        let status = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                      MemoryLayout<EventHotKeyID>.size, &identifier)
        guard status == noErr else { throw NSError(domain: "SetEventParameter", code: Int(status)) }
        // Rejected events may be handled by macOS; the counter is the actual acceptance evidence.
        _ = SendEventToEventTarget(event, GetApplicationEventTarget())
    }
}
