import Foundation

nonisolated struct AcceleratorPattern: Equatable, Sendable {
    var alt: Bool
    var shift: Bool
    var metaOrCtrl: Bool
    var metaOnly: Bool
    var ctrlOnly: Bool
    var code: String
}

nonisolated struct KeyPayload: Equatable, Sendable {
    var code: String
    var key: String
    var altKey: Bool
    var ctrlKey: Bool
    var metaKey: Bool
    var shiftKey: Bool
}

nonisolated enum AcceleratorMatch {
    private static let specialKeys: [String: String] = [
        "up": "ArrowUp",
        "down": "ArrowDown",
        "left": "ArrowLeft",
        "right": "ArrowRight",
        "space": "Space",
        "enter": "Enter",
        "return": "Enter",
        "tab": "Tab",
        "backspace": "Backspace",
        "delete": "Delete",
        "escape": "Escape",
        "esc": "Escape",
        "plus": "Equal",
        "minus": "Minus",
        "equal": "Equal"
    ]

    static func parseElectronAccelerator(_ accelerator: String) -> AcceleratorPattern? {
        let parts = accelerator.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        var alt = false
        var shift = false
        var metaOrCtrl = false
        var metaOnly = false
        var ctrlOnly = false
        var keyToken: String?

        for part in parts {
            switch part.lowercased() {
            case "commandorcontrol", "cmdorctrl":
                metaOrCtrl = true
            case "command", "cmd", "super", "meta":
                metaOnly = true
            case "control", "ctrl":
                ctrlOnly = true
            case "alt", "option", "opt":
                alt = true
            case "shift":
                shift = true
            default:
                keyToken = part
            }
        }

        guard let keyToken, let code = keyTokenToCode(keyToken) else { return nil }
        if !metaOrCtrl && !metaOnly && !ctrlOnly && !alt && !shift { return nil }
        return AcceleratorPattern(
            alt: alt,
            shift: shift,
            metaOrCtrl: metaOrCtrl,
            metaOnly: metaOnly,
            ctrlOnly: ctrlOnly,
            code: code
        )
    }

    static func payloadMatches(_ payload: KeyPayload, pattern: AcceleratorPattern) -> Bool {
        let codeOK =
            payload.code == pattern.code
            || (pattern.code.hasPrefix("Key") && payload.key.lowercased() == pattern.code.dropFirst(3).lowercased())
        guard codeOK else { return false }
        guard payload.altKey == pattern.alt else { return false }
        guard payload.shiftKey == pattern.shift else { return false }
        if pattern.metaOrCtrl {
            return payload.metaKey || payload.ctrlKey
        }
        return payload.metaKey == pattern.metaOnly && payload.ctrlKey == pattern.ctrlOnly
    }

    private static func keyTokenToCode(_ token: String) -> String? {
        let lower = token.lowercased()
        if let special = specialKeys[lower] { return special }
        if token == "=" { return "Equal" }
        if token == "-" { return "Minus" }
        if lower.range(of: #"^f\d{1,2}$"#, options: .regularExpression) != nil {
            return token.uppercased()
        }
        if lower.range(of: #"^\d$"#, options: .regularExpression) != nil {
            return "Digit\(token)"
        }
        if token.count == 1, token.first?.isLetter == true {
            return "Key\(token.uppercased())"
        }
        if lower.hasPrefix("num"), lower.count > 3 {
            return "Numpad\(token.dropFirst(3))"
        }
        let punct: [String: String] = [
            "[": "BracketLeft",
            "]": "BracketRight",
            "\\": "Backslash",
            ";": "Semicolon",
            "'": "Quote",
            ",": "Comma",
            ".": "Period",
            "/": "Slash",
            "`": "Backquote"
        ]
        return punct[token]
    }
}
