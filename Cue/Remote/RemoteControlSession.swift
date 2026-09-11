import AppKit
import CoreGraphics
import Foundation

nonisolated struct RemoteCursorState: Equatable, Sendable {
    var active: Bool
    var x: Double
    var y: Double
}

@MainActor
final class ClickShieldWindow {
    private var panel: NSPanel?

    func show() {
        hide()
        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        panel.level = .screenSaver
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

final class KeyboardEventTap: @unchecked Sendable {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeys: HotkeyMap = HotkeyCatalog.defaults
    var onKey: ((KeyPayload) -> Bool)?
    var onHotkey: ((HotkeyAction) -> Void)?
    var onPasteText: ((String) -> Void)?
    var onPasteImage: ((MessageAttachment) -> Void)?

    func updateHotkeys(_ map: HotkeyMap) {
        hotkeys = map
    }

    func start() {
        stop()
        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<KeyboardEventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: pointer
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let payload = KeyPayload(
            code: KeyCodeMap.code(for: keyCode),
            key: KeyCodeMap.key(for: keyCode),
            altKey: flags.contains(.maskAlternate),
            ctrlKey: flags.contains(.maskControl),
            metaKey: flags.contains(.maskCommand),
            shiftKey: flags.contains(.maskShift)
        )

        if payload.metaKey, payload.altKey, payload.code == "Escape" {
            return Unmanaged.passUnretained(event)
        }

        for (action, accelerator) in hotkeys {
            if let pattern = AcceleratorMatch.parseElectronAccelerator(accelerator),
               AcceleratorMatch.payloadMatches(payload, pattern: pattern) {
                DispatchQueue.main.async { self.onHotkey?(action) }
                if action == .quitApp { return Unmanaged.passUnretained(event) }
                return nil
            }
        }

        if payload.code == "Escape" {
            DispatchQueue.main.async { self.onHotkey?(.toggleRemoteControl) }
            return nil
        }

        if payload.metaKey, payload.code == "KeyV" {
            DispatchQueue.main.async {
                if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
                   let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
                    self.onPasteImage?(MessageAttachment(
                        id: UUID().uuidString,
                        mimeType: "image/jpeg",
                        name: "paste.jpg",
                        dataURL: "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                    ))
                } else if let text = NSPasteboard.general.string(forType: .string) {
                    self.onPasteText?(text)
                }
            }
            return nil
        }

        let consumed = onKey?(payload) ?? false
        return consumed ? nil : Unmanaged.passUnretained(event)
    }
}

nonisolated enum KeyCodeMap {
    static func code(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "KeyA"
        case 1: return "KeyS"
        case 2: return "KeyD"
        case 3: return "KeyF"
        case 4: return "KeyH"
        case 5: return "KeyG"
        case 6: return "KeyZ"
        case 7: return "KeyX"
        case 8: return "KeyC"
        case 9: return "KeyV"
        case 11: return "KeyB"
        case 12: return "KeyQ"
        case 13: return "KeyW"
        case 14: return "KeyE"
        case 15: return "KeyR"
        case 16: return "KeyY"
        case 17: return "KeyT"
        case 31: return "KeyO"
        case 32: return "KeyU"
        case 34: return "KeyI"
        case 35: return "KeyP"
        case 37: return "KeyL"
        case 38: return "KeyJ"
        case 40: return "KeyK"
        case 45: return "KeyN"
        case 46: return "KeyM"
        case 36, 76: return "Enter"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Backspace"
        case 53: return "Escape"
        case 123: return "ArrowLeft"
        case 124: return "ArrowRight"
        case 125: return "ArrowDown"
        case 126: return "ArrowUp"
        case 18: return "Digit1"
        case 19: return "Digit2"
        case 20: return "Digit3"
        case 21: return "Digit4"
        default: return "KeyUnknown"
        }
    }

    static func key(for keyCode: UInt16) -> String {
        let code = code(for: keyCode)
        if code.hasPrefix("Key") { return String(code.dropFirst(3)).lowercased() }
        return code
    }
}

@MainActor
@Observable
final class RemoteControlSession {
    private let shield = ClickShieldWindow()
    private let tap = KeyboardEventTap()
    private var monitor: Any?
    private var lastScreen = NSEvent.mouseLocation
    private var savedLevel: NSWindow.Level = .normal
    private var savedIgnoresMouse = false

    private(set) var active = false
    var cursor = RemoteCursorState(active: false, x: 0, y: 0)
    var onHotkey: ((HotkeyAction) -> Void)?
    var onText: ((String) -> Void)?
    var onImage: ((MessageAttachment) -> Void)?
    var onClick: ((CGPoint) -> Void)?

    func updateHotkeys(_ map: HotkeyMap) {
        tap.updateHotkeys(map)
    }

    func toggle(panel: CuePanelController, hotkeys: HotkeyMap) {
        if active {
            stop(panel: panel)
        } else {
            start(panel: panel, hotkeys: hotkeys)
        }
    }

    func start(panel: CuePanelController, hotkeys: HotkeyMap) {
        guard AccessibilityTrust.isTrusted else {
            AccessibilityTrust.request()
            return
        }
        active = true
        tap.updateHotkeys(hotkeys)
        savedLevel = panel.panel.level
        savedIgnoresMouse = panel.panel.ignoresMouseEvents
        panel.panel.level = .floating
        panel.panel.ignoresMouseEvents = true
        panel.reveal(passive: true)
        let size = panel.panel.contentLayoutRect.size
        cursor = RemoteCursorState(active: true, x: size.width / 2, y: size.height / 2)
        lastScreen = NSEvent.mouseLocation
        shield.show()
        tap.onHotkey = { [weak self] action in
            Task { @MainActor in
                if action == .toggleRemoteControl {
                    self?.stop(panel: panel)
                } else {
                    self?.onHotkey?(action)
                }
            }
        }
        tap.onPasteText = { [weak self] text in
            Task { @MainActor in self?.onText?(text) }
        }
        tap.onPasteImage = { [weak self] attachment in
            Task { @MainActor in self?.onImage?(attachment) }
        }
        tap.onKey = { payload in
            DispatchQueue.main.async {
                self.applyKey(payload)
            }
            return true
        }
        tap.start()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .scrollWheel]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouse(event, panel: panel)
            }
        }
    }

    func stop(panel: CuePanelController) {
        active = false
        cursor.active = false
        shield.hide()
        tap.stop()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel.panel.level = savedLevel
        panel.panel.ignoresMouseEvents = savedIgnoresMouse
    }

    private func handleMouse(_ event: NSEvent, panel: CuePanelController) {
        let screen = NSEvent.mouseLocation
        let size = panel.panel.contentLayoutRect.size
        let delta = RemoteCursorMath.applyScreenDelta(
            virtualX: cursor.x,
            virtualY: cursor.y,
            lastScreenX: lastScreen.x,
            lastScreenY: lastScreen.y,
            screenX: screen.x,
            screenY: screen.y,
            width: size.width,
            height: size.height
        )
        lastScreen = NSPoint(x: delta.lastScreenX, y: delta.lastScreenY)
        cursor.x = delta.virtualX
        cursor.y = delta.virtualY
        if event.type == .leftMouseDown {
            onClick?(CGPoint(x: cursor.x, y: size.height - cursor.y))
        }
    }

    private func applyKey(_ payload: KeyPayload) {
        if payload.code == "Backspace" {
            onText?("\u{8}")
            return
        }
        if payload.code == "Enter" {
            onHotkey?(.sendMessage)
            return
        }
        if payload.code == "Space" {
            onText?(" ")
            return
        }
        if payload.key.count == 1 {
            onText?(payload.shiftKey ? payload.key.uppercased() : payload.key)
        }
    }
}
