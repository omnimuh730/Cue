import AppKit
import Carbon
import CoreGraphics
import Foundation

/// Session-level keyboard tap that fires Cue's global hotkeys ahead of every other app.
///
/// Carbon's `RegisterEventHotKey` is first-come, first-served: whichever app registered a combo
/// first gets it, and anything with its own event tap (launchers, remappers, screen recorders)
/// sees the keystroke before the hotkey system does. A head-inserted session tap runs before all
/// of that. Matching keystrokes are swallowed so the focused app never sees them; everything else
/// passes straight through. Needs Accessibility; `GlobalHotkeyCenter` keeps Carbon registered as
/// the fallback when the tap cannot be installed.
final class HotkeyEventTap: @unchecked Sendable {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()
    private var bindings: [(action: HotkeyAction, key: CarbonHotkey)] = []

    /// Called on the main actor with the matched action.
    var onAction: (@MainActor (HotkeyAction) -> Void)?

    var isRunning: Bool { tap != nil }

    /// Binds the same key code + modifier combos Carbon would register, so the tap changes
    /// only who gets the keystroke first, never which keystrokes Cue claims.
    func update(_ map: HotkeyMap) {
        let next = map.compactMap { action, accelerator -> (action: HotkeyAction, key: CarbonHotkey)? in
            guard let pattern = AcceleratorMatch.parseElectronAccelerator(accelerator),
                  let key = CarbonHotkey.from(pattern)
            else { return nil }
            return (action, key)
        }
        lock.lock()
        bindings = next
        lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<HotkeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
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

    // The run-loop source lives on the main run loop, so this runs on main.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        case .keyDown:
            // Holding a combo must not re-fire a toggle every repeat.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  let action = match(event)
            else { return passThrough }
            let handler = onAction
            Task { @MainActor in handler?(action) }
            return nil
        default:
            return passThrough
        }
    }

    private func match(_ event: CGEvent) -> HotkeyAction? {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = CarbonHotkey.modifiers(from: event.flags)
        // Force Quit stays with the system no matter what is bound.
        if keyCode == 0x35, modifiers == UInt32(cmdKey | optionKey) { return nil }
        lock.lock()
        let bindings = bindings
        lock.unlock()
        return bindings.first { $0.key.keyCode == keyCode && $0.key.modifiers == modifiers }?.action
    }
}
