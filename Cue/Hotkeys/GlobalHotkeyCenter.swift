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
        KeyCodes.keyCode(for: code).map(UInt32.init)
    }
}
