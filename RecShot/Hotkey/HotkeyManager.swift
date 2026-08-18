import Carbon
import Foundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            recShotHotkeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x52534854), id: 1) // 'RSHT'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    func handle() {
        onHotkey?()
    }
}

private func recShotHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        HotkeyManager.shared.handle()
    }
    return noErr
}
