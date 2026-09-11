import AppKit
import Carbon
import Foundation

@MainActor
final class GlobalHotkeyCenter {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: HotkeyAction] = [:]
    var onAction: ((HotkeyAction) -> Void)?

    func register(_ map: HotkeyMap) {
        unregister()
        let handlerPtr: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<GlobalHotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            Task { @MainActor in
                if let action = center.actions[hotKeyID.id] {
                    center.onAction?(action)
                }
            }
            return noErr
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handlerPtr, 1, &eventType, userData, &handler)

        for (index, item) in HotkeyCatalog.items.enumerated() {
            guard let accelerator = map[item.id],
                  let parsed = AcceleratorMatch.parseElectronAccelerator(accelerator),
                  let carbon = CarbonHotkey.from(parsed)
            else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x43554521), id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                carbon.keyCode,
                carbon.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr {
                actions[hotKeyID.id] = item.id
                hotKeyRefs.append(ref)
            }
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs = []
        actions = [:]
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }
}

nonisolated struct CarbonHotkey: Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static func from(_ pattern: AcceleratorPattern) -> CarbonHotkey? {
        guard let keyCode = keyCode(for: pattern.code) else { return nil }
        var modifiers: UInt32 = 0
        if pattern.shift { modifiers |= UInt32(shiftKey) }
        if pattern.alt { modifiers |= UInt32(optionKey) }
        if pattern.metaOrCtrl || pattern.metaOnly { modifiers |= UInt32(cmdKey) }
        if pattern.ctrlOnly { modifiers |= UInt32(controlKey) }
        return CarbonHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private static func keyCode(for code: String) -> UInt32? {
        switch code {
        case "KeyA": return 0x00
        case "KeyS": return 0x01
        case "KeyD": return 0x02
        case "KeyF": return 0x03
        case "KeyH": return 0x04
        case "KeyG": return 0x05
        case "KeyZ": return 0x06
        case "KeyX": return 0x07
        case "KeyC": return 0x08
        case "KeyV": return 0x09
        case "KeyB": return 0x0B
        case "KeyQ": return 0x0C
        case "KeyW": return 0x0D
        case "KeyE": return 0x0E
        case "KeyR": return 0x0F
        case "KeyY": return 0x10
        case "KeyT": return 0x11
        case "Digit1": return 0x12
        case "Digit2": return 0x13
        case "Digit3": return 0x14
        case "Digit4": return 0x15
        case "Digit6": return 0x16
        case "Digit5": return 0x17
        case "Equal": return 0x18
        case "Digit9": return 0x19
        case "Digit7": return 0x1A
        case "Minus": return 0x1B
        case "Digit8": return 0x1C
        case "Digit0": return 0x1D
        case "KeyO": return 0x1F
        case "KeyU": return 0x20
        case "KeyI": return 0x22
        case "KeyP": return 0x23
        case "Enter": return 0x24
        case "KeyL": return 0x25
        case "KeyJ": return 0x26
        case "KeyK": return 0x28
        case "KeyN": return 0x2D
        case "KeyM": return 0x2E
        case "Tab": return 0x30
        case "Space": return 0x31
        case "Backspace": return 0x33
        case "Escape": return 0x35
        case "ArrowLeft": return 0x7B
        case "ArrowRight": return 0x7C
        case "ArrowDown": return 0x7D
        case "ArrowUp": return 0x7E
        case "Numpad2": return 0x54
        case "Numpad4": return 0x56
        case "Numpad6": return 0x58
        case "Numpad8": return 0x5B
        default: return nil
        }
    }
}
