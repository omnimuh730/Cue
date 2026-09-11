import AppKit
import CoreGraphics
import Foundation

nonisolated enum RemoteMouseButton: Sendable {
    case left
    case right
    case other
}

nonisolated enum RemoteInputEvent: Sendable {
    /// Relative pointer motion in points (Quartz orientation: +y is down).
    case move(dx: Double, dy: Double)
    case buttonDown(RemoteMouseButton, clickCount: Int, flags: CGEventFlags)
    case buttonUp(RemoteMouseButton, clickCount: Int, flags: CGEventFlags)
    /// The original scroll event, copied so its precise deltas and phases survive.
    case scroll(CGEvent)
    case key(RemoteKeyStroke)
}

nonisolated struct RemoteKeyStroke: Sendable {
    var payload: KeyPayload
    /// Characters the keystroke would insert, honoring layout and Shift/Option.
    var characters: String
    var isRepeat: Bool
}

/// Session-level CGEvent tap that owns all pointer and keyboard input while remote control
/// is active. Motion passes through (the OS cursor keeps moving over the click shield);
/// clicks, wheel, and keys are swallowed so the focused app never sees them, then replayed
/// into Cue at the virtual cursor. Force Quit (⌘⌥⎋) is never consumed.
final class RemoteInputTap: @unchecked Sendable {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()
    private var hotkeys: HotkeyMap = HotkeyCatalog.defaults

    /// Called on the main thread for every swallowed or observed event.
    var onEvent: ((RemoteInputEvent) -> Void)?
    /// Called on the main thread when a keystroke matches a global hotkey. Return `true`
    /// to let the event continue to the system (used for Quit so Carbon also sees it).
    var onHotkey: ((HotkeyAction) -> Bool)?

    var isRunning: Bool { tap != nil }

    func updateHotkeys(_ map: HotkeyMap) {
        lock.lock()
        hotkeys = map
        lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        stop()
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<RemoteInputTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: pointer
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // The tap's run-loop source lives on the main run loop, so this already runs on main.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            if dx != 0 || dy != 0 {
                deliver(.move(dx: dx, dy: dy))
            }
            return passThrough
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let count = max(1, Int(event.getIntegerValueField(.mouseEventClickState)))
            deliver(.buttonDown(button(for: type), clickCount: count, flags: event.flags))
            return nil
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let count = max(1, Int(event.getIntegerValueField(.mouseEventClickState)))
            deliver(.buttonUp(button(for: type), clickCount: count, flags: event.flags))
            return nil
        case .scrollWheel:
            if let copy = event.copy() {
                deliver(.scroll(copy))
            }
            return nil
        case .flagsChanged:
            return passThrough
        case .keyUp:
            // Key ups never reach the focused app while remote is on; the matching key down
            // was swallowed, so an orphaned key up would only confuse it.
            return isForceQuit(event) ? passThrough : nil
        case .keyDown:
            return handleKeyDown(event) ? nil : passThrough
        default:
            return passThrough
        }
    }

    /// Returns `true` when the key down was consumed.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        if isForceQuit(event) { return false }
        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let code = KeyCodes.code(for: keyCode)
        let payload = KeyPayload(
            code: code,
            key: KeyCodes.key(for: code),
            altKey: flags.contains(.maskAlternate),
            ctrlKey: flags.contains(.maskControl),
            metaKey: flags.contains(.maskCommand),
            shiftKey: flags.contains(.maskShift)
        )

        lock.lock()
        let map = hotkeys
        lock.unlock()
        for (action, accelerator) in map {
            guard let pattern = AcceleratorMatch.parseElectronAccelerator(accelerator),
                  AcceleratorMatch.payloadMatches(payload, pattern: pattern)
            else { continue }
            let forward = onMain { self.onHotkey?(action) ?? false }
            return !forward
        }

        let stroke = RemoteKeyStroke(
            payload: payload,
            characters: characters(of: event),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        deliver(.key(stroke))
        return true
    }

    private func isForceQuit(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        return keyCode == 0x35 && event.flags.contains(.maskCommand) && event.flags.contains(.maskAlternate)
    }

    private func characters(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: length)
    }

    private func button(for type: CGEventType) -> RemoteMouseButton {
        switch type {
        case .leftMouseDown, .leftMouseUp: .left
        case .rightMouseDown, .rightMouseUp: .right
        default: .other
        }
    }

    private func deliver(_ event: RemoteInputEvent) {
        onMain { self.onEvent?(event) }
    }

    private func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
