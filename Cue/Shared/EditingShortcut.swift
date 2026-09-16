import AppKit

/// The Edit-menu shortcuts a text view expects to receive, resolved from a key event.
///
/// macOS dispatches menu key equivalents only to the active application. Cue's panel is a
/// non-activating window that is key while another app stays active, so its Edit menu never
/// sees ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z; text views have to send those actions themselves.
nonisolated enum EditingShortcut {
    static func action(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        return action(key: key, command: modifiers.contains(.command), shift: modifiers.contains(.shift), other: !modifiers.subtracting([.command, .shift]).isEmpty)
    }

    static func action(key: String, command: Bool, shift: Bool, other: Bool) -> Selector? {
        guard command, !other else { return nil }
        switch (key, shift) {
        case ("c", false): return #selector(NSText.copy(_:))
        case ("x", false): return #selector(NSText.cut(_:))
        case ("v", false): return #selector(NSText.paste(_:))
        case ("v", true): return #selector(NSTextView.pasteAsPlainText(_:))
        case ("a", false): return #selector(NSText.selectAll(_:))
        case ("z", false): return Selector(("undo:"))
        case ("z", true): return Selector(("redo:"))
        default: return nil
        }
    }
}
