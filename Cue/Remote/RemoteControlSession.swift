import AppKit
import CoreGraphics
import Foundation

nonisolated struct RemoteCursorState: Equatable, Sendable {
    var active: Bool
    /// Content coordinates of the Cue panel, origin top-left (SwiftUI space).
    var x: Double
    var y: Double
}

/// Invisible fullscreen panel under the real cursor. It exists so hover and any click the
/// event tap misses (for example while the tap is re-enabled after a timeout) lands on Cue
/// instead of the interview app. It never becomes key.
@MainActor
final class ClickShieldWindow {
    private var panel: NSPanel?

    func show(on screen: NSScreen) {
        hide()
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.004)
        panel.level = .screenSaver
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = ShieldView(frame: NSRect(origin: .zero, size: screen.frame.size))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    var frame: NSRect? { panel?.frame }

    private final class ShieldView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {}
        override func rightMouseDown(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) {}
        override func otherMouseDown(with event: NSEvent) {}
        override func otherMouseUp(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) {}
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }
    }
}

/// Passive remote control: a virtual cursor inside Cue driven by relative mouse deltas, with
/// clicks, wheel, typing and paste swallowed at the session event tap and replayed into the
/// Cue panel. The interview app keeps OS focus the whole time. Escape or the hotkey exits.
@MainActor
@Observable
final class RemoteControlSession {
    private let shield = ClickShieldWindow()
    private let tap = RemoteInputTap()
    private weak var panelController: CuePanelController?
    private var savedLevel: NSWindow.Level = .normal
    private var savedIgnoresMouse = false
    private var eventNumber = 0
    private var pressedButton: RemoteMouseButton?
    private var lastHoverReplay = Date.distantPast

    private(set) var active = false
    var cursor = RemoteCursorState(active: false, x: 0, y: 0)
    /// Latest problem with entering remote mode, for the UI notice.
    var lastError: String?
    var onHotkey: ((HotkeyAction) -> Void)?
    var onText: ((String) -> Void)?
    var onImage: ((MessageAttachment) -> Void)?

    func updateHotkeys(_ map: HotkeyMap) {
        tap.updateHotkeys(map)
    }

    func toggle(panel: CuePanelController, hotkeys: HotkeyMap) {
        if active {
            stop()
        } else {
            start(panel: panel, hotkeys: hotkeys)
        }
    }

    func start(panel: CuePanelController, hotkeys: HotkeyMap) {
        guard !active else { return }
        guard AccessibilityTrust.isTrusted else {
            lastError = "Grant Cue Accessibility access in System Settings to use remote control."
            AccessibilityTrust.request()
            return
        }
        tap.updateHotkeys(hotkeys)
        tap.onHotkey = { [weak self] action in
            guard let self else { return false }
            if action == .toggleRemoteControl {
                stop()
                return false
            }
            onHotkey?(action)
            return action == .quitApp
        }
        tap.onEvent = { [weak self] event in
            self?.handle(event)
        }
        guard tap.start() else {
            lastError = "Could not install the input tap. Check Accessibility and Input Monitoring for Cue."
            return
        }

        panelController = panel
        savedLevel = panel.panel.level
        savedIgnoresMouse = panel.panel.ignoresMouseEvents
        panel.panel.allowsKeyStatus = false
        panel.panel.level = .floating
        panel.panel.ignoresMouseEvents = true
        panel.panel.acceptsMouseMovedEvents = true
        panel.reveal(passive: true)

        let size = panel.contentSize
        cursor = RemoteCursorState(active: true, x: size.width / 2, y: size.height / 2)
        pressedButton = nil
        active = true
        lastError = nil

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? panel.panel.screen
            ?? NSScreen.main
        if let screen { shield.show(on: screen) }
    }

    func stop() {
        guard active else { return }
        active = false
        cursor.active = false
        tap.stop()
        shield.hide()
        if let pressed = pressedButton, let panelController {
            // Never leave a view stuck in a pressed state.
            replay(button: pressed, down: false, clickCount: 1, flags: [], panel: panelController)
        }
        pressedButton = nil
        if let panelController {
            panelController.panel.level = savedLevel
            panelController.panel.ignoresMouseEvents = savedIgnoresMouse
            panelController.panel.acceptsMouseMovedEvents = false
            panelController.panel.allowsKeyStatus = true
        }
        panelController = nil
    }

    // MARK: - Input

    private func handle(_ event: RemoteInputEvent) {
        guard active, let panel = panelController else { return }
        switch event {
        case .move(let dx, let dy):
            let size = panel.contentSize
            let next = RemoteCursorMath.applyDelta(
                virtualX: cursor.x,
                virtualY: cursor.y,
                dx: dx,
                dy: dy,
                width: size.width,
                height: size.height
            )
            guard next.moved else { return }
            cursor.x = next.virtualX
            cursor.y = next.virtualY
            if pressedButton == .left {
                replay(type: .leftMouseDragged, clickCount: 1, flags: [], panel: panel)
            } else if Date().timeIntervalSince(lastHoverReplay) > 1.0 / 30.0 {
                lastHoverReplay = Date()
                replay(type: .mouseMoved, clickCount: 0, flags: [], panel: panel)
            }
        case .buttonDown(let button, let clickCount, let flags):
            pressedButton = button
            replay(button: button, down: true, clickCount: clickCount, flags: flags, panel: panel)
        case .buttonUp(let button, let clickCount, let flags):
            pressedButton = nil
            replay(button: button, down: false, clickCount: clickCount, flags: flags, panel: panel)
        case .scroll(let cgEvent):
            guard let nsEvent = NSEvent(cgEvent: cgEvent) else { return }
            panel.replayScroll(nsEvent, at: CGPoint(x: cursor.x, y: cursor.y))
        case .key(let stroke):
            apply(stroke)
        }
    }

    private func replay(button: RemoteMouseButton, down: Bool, clickCount: Int, flags: CGEventFlags, panel: CuePanelController) {
        let type: NSEvent.EventType = switch (button, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        case (.other, true): .otherMouseDown
        case (.other, false): .otherMouseUp
        }
        replay(type: type, clickCount: clickCount, flags: flags, panel: panel)
    }

    private func replay(type: NSEvent.EventType, clickCount: Int, flags: CGEventFlags, panel: CuePanelController) {
        let size = panel.contentSize
        let location = NSPoint(x: cursor.x, y: size.height - cursor.y)
        eventNumber += 1
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue) & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.panel.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: clickCount,
            pressure: type == .leftMouseDown ? 1 : 0
        ) else { return }
        panel.replay(event)
    }

    private func apply(_ stroke: RemoteKeyStroke) {
        let payload = stroke.payload
        switch payload.code {
        case "Escape":
            stop()
        case "Enter":
            if payload.shiftKey || payload.altKey {
                onText?("\n")
            } else {
                onHotkey?(.sendMessage)
            }
        case "Backspace":
            onText?(payload.altKey ? RemoteTextEdit.deleteWord : RemoteTextEdit.deleteBackward)
        case "Tab", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Delete",
             "Home", "End", "PageUp", "PageDown":
            break
        default:
            if payload.metaKey || payload.ctrlKey {
                if payload.code == "KeyV" || payload.key == "v" { paste() }
                return
            }
            let text = stroke.characters
            guard !text.isEmpty, text.unicodeScalars.allSatisfy({ !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 }) else { return }
            onText?(text)
        }
    }

    private func paste() {
        let pasteboard = NSPasteboard.general
        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
           let dataURL = ImageAttachmentEncoder.jpegDataURL(image) {
            onImage?(MessageAttachment(
                mimeType: "image/jpeg",
                name: "paste-\(Int(Date().timeIntervalSince1970)).jpg",
                dataURL: dataURL
            ))
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            onText?(text)
        }
    }
}

/// Sentinel strings the remote keyboard sends through `onText` for edits that are not insertions.
nonisolated enum RemoteTextEdit {
    static let deleteBackward = "\u{8}"
    static let deleteWord = "\u{17}"

    /// Applies an `onText` payload to a draft string.
    static func apply(_ text: String, to draft: inout String) {
        switch text {
        case deleteBackward:
            if !draft.isEmpty { draft.removeLast() }
        case deleteWord:
            while let last = draft.last, last.isWhitespace { draft.removeLast() }
            while let last = draft.last, !last.isWhitespace { draft.removeLast() }
        default:
            draft += text
        }
    }
}
