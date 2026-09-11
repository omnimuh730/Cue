import Foundation

/// Bidirectional map between macOS virtual key codes and DOM-style `code` names
/// (`KeyA`, `Digit1`, `ArrowUp`, `Numpad4`…). Shared by hotkey registration, the
/// remote keyboard tap, and the settings recorder so no table drifts.
nonisolated enum KeyCodes {
    static let codeByKeyCode: [UInt16: String] = [
        0x00: "KeyA", 0x01: "KeyS", 0x02: "KeyD", 0x03: "KeyF", 0x04: "KeyH", 0x05: "KeyG",
        0x06: "KeyZ", 0x07: "KeyX", 0x08: "KeyC", 0x09: "KeyV", 0x0B: "KeyB",
        0x0C: "KeyQ", 0x0D: "KeyW", 0x0E: "KeyE", 0x0F: "KeyR", 0x10: "KeyY", 0x11: "KeyT",
        0x12: "Digit1", 0x13: "Digit2", 0x14: "Digit3", 0x15: "Digit4", 0x16: "Digit6",
        0x17: "Digit5", 0x18: "Equal", 0x19: "Digit9", 0x1A: "Digit7", 0x1B: "Minus",
        0x1C: "Digit8", 0x1D: "Digit0", 0x1E: "BracketRight", 0x1F: "KeyO", 0x20: "KeyU",
        0x21: "BracketLeft", 0x22: "KeyI", 0x23: "KeyP", 0x24: "Enter", 0x25: "KeyL",
        0x26: "KeyJ", 0x27: "Quote", 0x28: "KeyK", 0x29: "Semicolon", 0x2A: "Backslash",
        0x2B: "Comma", 0x2C: "Slash", 0x2D: "KeyN", 0x2E: "KeyM", 0x2F: "Period",
        0x30: "Tab", 0x31: "Space", 0x32: "Backquote", 0x33: "Backspace", 0x35: "Escape",
        0x4C: "Enter",
        0x52: "Numpad0", 0x53: "Numpad1", 0x54: "Numpad2", 0x55: "Numpad3", 0x56: "Numpad4",
        0x57: "Numpad5", 0x58: "Numpad6", 0x59: "Numpad7", 0x5B: "Numpad8", 0x5C: "Numpad9",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3", 0x64: "F8", 0x65: "F9", 0x67: "F11",
        0x69: "F13", 0x6B: "F14", 0x6D: "F10", 0x6F: "F12", 0x71: "F15", 0x72: "Help",
        0x73: "Home", 0x74: "PageUp", 0x75: "Delete", 0x76: "F4", 0x77: "End", 0x78: "F2",
        0x79: "PageDown", 0x7A: "F1",
        0x7B: "ArrowLeft", 0x7C: "ArrowRight", 0x7D: "ArrowDown", 0x7E: "ArrowUp"
    ]

    static let keyCodeByCode: [String: UInt16] = {
        var map: [String: UInt16] = [:]
        for (keyCode, code) in codeByKeyCode {
            if let existing = map[code], existing <= keyCode { continue }
            map[code] = keyCode
        }
        return map
    }()

    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static func code(for keyCode: UInt16) -> String {
        codeByKeyCode[keyCode] ?? "Unidentified"
    }

    static func keyCode(for code: String) -> UInt16? {
        keyCodeByCode[code]
    }

    /// Electron-style `key` for accelerator matching: letters lowercased, everything else the code.
    static func key(for code: String) -> String {
        if code.hasPrefix("Key"), code.count == 4 { return String(code.dropFirst(3)).lowercased() }
        return code
    }
}
