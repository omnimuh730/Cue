import AppKit
import Foundation

nonisolated enum HotkeyFormat {
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static func accelerator(from event: NSEvent) -> String? {
        accelerator(keyCode: event.keyCode, flags: event.modifierFlags, characters: event.charactersIgnoringModifiers)
    }

    static func accelerator(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> String? {
        if keyCode == 53 { return nil }
        if modifierKeyCodes.contains(keyCode) { return nil }

        var parts: [String] = []
        if flags.contains(.command) || flags.contains(.control) {
            parts.append("CommandOrControl")
        }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }

        guard let key = token(forKeyCode: keyCode, characters: characters) else { return nil }
        parts.append(key)
        guard parts.count >= 2 else { return nil }
        return parts.joined(separator: "+")
    }

    static func keycaps(for accelerator: String) -> [String] {
        accelerator
            .split(separator: "+")
            .map { cap(for: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    static func displayLabel(for accelerator: String) -> String {
        keycaps(for: accelerator).joined(separator: " ")
    }

    static func isRegisterable(_ accelerator: String) -> Bool {
        guard let pattern = AcceleratorMatch.parseElectronAccelerator(accelerator) else { return false }
        return CarbonHotkey.from(pattern) != nil
    }

    private static func cap(for token: String) -> String {
        switch token.lowercased() {
        case "commandorcontrol", "cmdorctrl", "command", "cmd", "meta", "super":
            return "⌘"
        case "control", "ctrl":
            return "⌃"
        case "alt", "option", "opt":
            return "⌥"
        case "shift":
            return "⇧"
        case "up":
            return "↑"
        case "down":
            return "↓"
        case "left":
            return "←"
        case "right":
            return "→"
        case "enter", "return":
            return "↩"
        case "tab":
            return "⇥"
        case "space":
            return "Space"
        case "backspace":
            return "⌫"
        case "delete":
            return "⌦"
        case "escape", "esc":
            return "Esc"
        default:
            let lower = token.lowercased()
            if lower.hasPrefix("num"), token.count > 3 {
                return String(token.dropFirst(3))
            }
            return token
        }
    }

    private static func token(forKeyCode keyCode: UInt16, characters: String?) -> String? {
        if let mapped = tokenByKeyCode[keyCode] { return mapped }
        guard let characters, let scalar = characters.unicodeScalars.first else { return nil }
        if CharacterSet.letters.contains(scalar) {
            return String(characters).uppercased()
        }
        if CharacterSet.decimalDigits.contains(scalar) {
            return String(characters)
        }
        return nil
    }

    private static let tokenByKeyCode: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B",
        0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
        0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x24: "Enter", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
        0x30: "Tab", 0x31: "Space", 0x32: "`", 0x33: "Backspace",
        0x35: "Escape", 0x75: "Delete",
        0x7B: "Left", 0x7C: "Right", 0x7D: "Down", 0x7E: "Up",
        0x52: "num0", 0x53: "num1", 0x54: "num2", 0x55: "num3",
        0x56: "num4", 0x57: "num5", 0x58: "num6", 0x59: "num7",
        0x5B: "num8", 0x5C: "num9"
    ]
}
