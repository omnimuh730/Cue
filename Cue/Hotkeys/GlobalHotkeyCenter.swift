import AppKit
import Carbon
import Foundation

/// Registers Cue's global hotkeys two ways at once: a head-inserted event tap so they beat every
/// other app's bindings, and Carbon hot keys as the fallback for when the tap cannot be installed
/// (no Accessibility grant). A keystroke the tap swallows never reaches Carbon, so an action
/// fires once either way.
@MainActor
final class GlobalHotkeyCenter {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: HotkeyAction] = [:]
    private let tap = HotkeyEventTap()
    var onAction: ((HotkeyAction) -> Void)?

    private var activationObserver: NSObjectProtocol?

    /// True while the event tap is live, i.e. Cue's hotkeys win over other apps'.
    var hasPriority: Bool { tap.isRunning }

    init() {
        // Accessibility can be granted while Cue is running; pick the tap up next time the app
        // comes forward rather than waiting for a settings save.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPriority() }
        }
    }

    /// Starts the priority tap if Accessibility has been granted since the last attempt.
    func refreshPriority() {
        guard !tap.isRunning, !actions.isEmpty, AccessibilityTrust.isTrusted else { return }
        tap.start()
    }

    func register(_ map: HotkeyMap) {
        unregister()
        tap.update(map)
        tap.onAction = { [weak self] action in
            self?.onAction?(action)
        }
        if AccessibilityTrust.isTrusted {
            tap.start()
        }
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
        tap.stop()
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

    /// The Carbon modifier mask for a keyboard event: ⌘ ⇧ ⌥ ⌃ only, so caps lock, fn, and the
    /// numeric-pad flag never keep a combo from matching.
    static func modifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private static func keyCode(for code: String) -> UInt32? {
        KeyCodes.keyCode(for: code).map(UInt32.init)
    }
}
