import Carbon
import Foundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onHotkey: (() -> Void)?
    var onRecordHotkey: (() -> Void)?

    private var captureHotKeyRef: EventHotKeyRef?
    private var recordHotKeyRef: EventHotKeyRef?
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

        let captureHotKeyID = EventHotKeyID(signature: OSType(0x52534854), id: 1) // 'RSHT'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(cmdKey | optionKey),
            captureHotKeyID,
            GetApplicationEventTarget(),
            0,
            &captureHotKeyRef
        )

        let recordHotKeyID = EventHotKeyID(signature: OSType(0x52534854), id: 2) // 'RSHT'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(cmdKey | optionKey),
            recordHotKeyID,
            GetApplicationEventTarget(),
            0,
            &recordHotKeyRef
        )
    }

    func unregister() {
        if let captureHotKeyRef {
            UnregisterEventHotKey(captureHotKeyRef)
            self.captureHotKeyRef = nil
        }
        if let recordHotKeyRef {
            UnregisterEventHotKey(recordHotKeyRef)
            self.recordHotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    func handle(_ event: EventRef?) {
        guard let event else { return }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return }

        if hotKeyID.id == 1 {
            onHotkey?()
        } else if hotKeyID.id == 2 {
            onRecordHotkey?()
        }
    }
}

private func recShotHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        HotkeyManager.shared.handle(event)
    }
    return noErr
}
