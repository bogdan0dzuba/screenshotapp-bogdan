import Carbon
import Foundation
import ScreenshotCore

final class GlobalHotKeyService {
    enum RegistrationError: LocalizedError {
        case conflict(HotKey)
        case missingModifier
        case failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .conflict(hotKey):
                "Сочетание \(HotKeyDisplayFormatter.symbolic(hotKey)) уже занято macOS или другим приложением. Выберите другое."
            case .missingModifier:
                "Добавьте к букве хотя бы один модификатор: Command, Shift, Option или Control."
            case let .failed(status): "Не удалось назначить горячую клавишу (код \(status))"
            }
        }
    }

    private var registration = HotKeyRegistrationStore<EventHotKeyRef>()
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private var nextIdentifier: UInt32 = 1
    private var activeIdentifier: UInt32?
    private var handlerInstallationStatus: OSStatus = noErr
    private let handlerSignature: OSType
    private let allowsUnmodifiedEscape: Bool

    var registeredHotKey: HotKey? { registration.hotKey }

    init(signature: OSType = 0x53485346, allowsUnmodifiedEscape: Bool = false) {
        handlerSignature = signature
        self.allowsUnmodifiedEscape = allowsUnmodifiedEscape
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerInstallationStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == service.handlerSignature,
                      identifier.id == service.activeIdentifier else { return OSStatus(eventNotHandledErr) }
                let queueDelay = GlobalHotKeyService.deliveryDelayMilliseconds(
                    eventTime: GetEventTime(event), now: GetCurrentEventTime()
                )
                let hidDelay = GlobalHotKeyService.deliveryDelayMilliseconds(
                    eventTime: 0,
                    now: CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
                )
                CaptureTelemetry.logger.notice("hotkey_received key_code=\(service.registeredHotKey?.keyCode ?? UInt32.max, privacy: .public) queue_delay_ms=\(queueDelay, privacy: .public) hid_delay_ms=\(hidDelay, privacy: .public)")
                service.action?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    static func deliveryDelayMilliseconds(eventTime: TimeInterval, now: TimeInterval) -> Int {
        let interval = now - eventTime
        guard interval.isFinite, interval >= 0, interval < Double(Int.max) / 1000 else { return -1 }
        return Int(interval * 1000)
    }

    deinit {
        registration.unregisterCurrent { UnregisterEventHotKey($0) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(_ hotKey: HotKey, action: @escaping () -> Void) throws {
        guard handlerInstallationStatus == noErr, eventHandlerRef != nil else {
            CaptureTelemetry.logger.error("hotkey_handler_failed status=\(self.handlerInstallationStatus)")
            throw RegistrationError.failed(handlerInstallationStatus == noErr ? OSStatus(eventNotHandledErr) : handlerInstallationStatus)
        }
        guard !hotKey.modifiers.isEmpty || (allowsUnmodifiedEscape && hotKey.keyCode == UInt32(kVK_Escape)) else {
            throw RegistrationError.missingModifier
        }
        var carbonModifiers: UInt32 = 0
        if hotKey.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if hotKey.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if hotKey.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if hotKey.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if registration.hotKey == hotKey, registration.handle != nil {
            self.action = action
            return
        }
        let identifier = EventHotKeyID(signature: handlerSignature, id: nextIdentifier)
        nextIdentifier &+= 1

        try registration.replace(
            with: hotKey,
            register: {
                var candidateRef: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    hotKey.keyCode,
                    carbonModifiers,
                    identifier,
                    GetApplicationEventTarget(),
                    0,
                    &candidateRef
                )
                guard status == noErr, let candidateRef else {
                    if let candidateRef {
                        UnregisterEventHotKey(candidateRef)
                    }
                    if status == eventHotKeyExistsErr {
                        throw RegistrationError.conflict(hotKey)
                    }
                    throw RegistrationError.failed(status)
                }
                return candidateRef
            },
            unregister: { UnregisterEventHotKey($0) }
        )
        activeIdentifier = identifier.id
        self.action = action
        CaptureTelemetry.logger.info("hotkey_registered key_code=\(hotKey.keyCode, privacy: .public)")
    }

    func unregister() {
        activeIdentifier = nil
        action = nil
        registration.unregisterCurrent { UnregisterEventHotKey($0) }
    }

    var activeEventIdentifier: UInt32? { activeIdentifier }
}
