import Carbon
import Foundation
import ScreenshotCore

final class GlobalHotKeyService {
    enum RegistrationError: LocalizedError {
        case failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .failed(status): "Не удалось назначить горячую клавишу (код \(status))"
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

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
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(_ hotKey: HotKey, action: @escaping () -> Void) throws {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        self.action = action
        var carbonModifiers: UInt32 = 0
        if hotKey.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if hotKey.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if hotKey.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if hotKey.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { throw RegistrationError.failed(status) }
        CaptureTelemetry.logger.info("hotkey_registered key_code=\(hotKey.keyCode, privacy: .public)")
    }

    private static let signature: OSType = 0x53485346 // SHSF
}
