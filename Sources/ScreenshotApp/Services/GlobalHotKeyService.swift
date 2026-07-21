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

    var registeredHotKey: HotKey? { registration.hotKey }

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                CaptureTelemetry.logger.info("hotkey_received")
                service.action?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit {
        registration.unregisterCurrent { UnregisterEventHotKey($0) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(_ hotKey: HotKey, action: @escaping () -> Void) throws {
        guard !hotKey.modifiers.isEmpty else { throw RegistrationError.missingModifier }
        var carbonModifiers: UInt32 = 0
        if hotKey.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if hotKey.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if hotKey.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if hotKey.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        let identifier = EventHotKeyID(signature: Self.signature, id: nextIdentifier)
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
        self.action = action
        CaptureTelemetry.logger.info("hotkey_registered key_code=\(hotKey.keyCode, privacy: .public)")
    }

    private static let signature: OSType = 0x53485346 // SHSF
}
