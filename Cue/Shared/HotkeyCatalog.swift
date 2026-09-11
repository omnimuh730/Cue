import Foundation

nonisolated enum HotkeyAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case toggleShowHide
    case opacityUp
    case opacityDown
    case toggleAlwaysOnTop
    case moveWindowLeft
    case moveWindowUp
    case moveWindowRight
    case moveWindowDown
    case resizeWider
    case resizeNarrower
    case resizeTaller
    case resizeShorter
    case toggleSidebar
    case toggleAudioAuto
    case listenStartStop
    case listenOff
    case clearAudioCache
    case cycleModel
    case cycleEffort
    case sendMessage
    case newChat
    case toggleMermaidMode
    case screenshotDesktop
    case screenshotRegion
    case toggleRemoteControl
    case quitApp

    var id: String { rawValue }
}

nonisolated enum HotkeyGroup: String, Sendable {
    case window = "Window"
    case audio = "Audio"
    case chat = "Chat"
    case capture = "Capture"
}

nonisolated struct HotkeyDefinition: Equatable, Sendable, Identifiable {
    var id: HotkeyAction
    var label: String
    var description: String
    var group: HotkeyGroup
}

typealias HotkeyMap = [HotkeyAction: String]

nonisolated enum HotkeyCatalog {
    static let items: [HotkeyDefinition] = [
        .init(id: .toggleShowHide, label: "Show / hide Cue", description: "Toggle the Cue window from anywhere", group: .window),
        .init(id: .opacityUp, label: "Transparency up (more opaque)", description: "Increase window opacity", group: .window),
        .init(id: .opacityDown, label: "Transparency down (more clear)", description: "Decrease window opacity", group: .window),
        .init(id: .toggleAlwaysOnTop, label: "Always on top", description: "Pin Cue above other windows", group: .window),
        .init(id: .moveWindowLeft, label: "Move window left", description: "Nudge Cue left without stealing focus", group: .window),
        .init(id: .moveWindowUp, label: "Move window up", description: "Nudge Cue up without stealing focus", group: .window),
        .init(id: .moveWindowRight, label: "Move window right", description: "Nudge Cue right without stealing focus", group: .window),
        .init(id: .moveWindowDown, label: "Move window down", description: "Nudge Cue down without stealing focus", group: .window),
        .init(id: .resizeWider, label: "Resize wider", description: "Grow the window horizontally without stealing focus", group: .window),
        .init(id: .resizeNarrower, label: "Resize narrower", description: "Shrink the window horizontally without stealing focus", group: .window),
        .init(id: .resizeTaller, label: "Resize taller", description: "Grow the window vertically without stealing focus", group: .window),
        .init(id: .resizeShorter, label: "Resize shorter", description: "Shrink the window vertically without stealing focus", group: .window),
        .init(id: .toggleSidebar, label: "Toggle left menu", description: "Collapse or expand the chat sidebar", group: .window),
        .init(id: .toggleRemoteControl, label: "Passive remote control", description: "Virtual cursor; clicks/keys/paste go to Cue", group: .window),
        .init(id: .quitApp, label: "Quit Cue", description: "Quit the app from anywhere", group: .window),
        .init(id: .toggleAudioAuto, label: "Audio auto mode", description: "Toggle automatic VAD listening vs manual hotkey-only", group: .audio),
        .init(id: .listenStartStop, label: "Start / stop listening", description: "Arm or disarm speaker listen", group: .audio),
        .init(id: .listenOff, label: "Turn off listening", description: "Disarm speaker listen and stop manual capture", group: .audio),
        .init(id: .clearAudioCache, label: "Clear audio / draft transcript", description: "Forget recording so far and clear the composer draft", group: .audio),
        .init(id: .cycleModel, label: "Cycle chat model", description: "Switch to the next OpenAI chat model", group: .chat),
        .init(id: .cycleEffort, label: "Cycle reasoning effort", description: "Switch to the next thinking effort", group: .chat),
        .init(id: .sendMessage, label: "Send message", description: "Same as the composer send button", group: .chat),
        .init(id: .newChat, label: "New chat", description: "Start a fresh conversation", group: .chat),
        .init(id: .toggleMermaidMode, label: "Toggle Mermaid diagram / code", description: "Switch Mermaid blocks between diagram and source code", group: .chat),
        .init(id: .screenshotDesktop, label: "Desktop screenshot", description: "Capture the full desktop and attach it", group: .capture),
        .init(id: .screenshotRegion, label: "Region screenshot", description: "Drag to select a desktop region and attach it", group: .capture)
    ]

    static let defaults: HotkeyMap = [
        .toggleShowHide: "CommandOrControl+Shift+H",
        .opacityUp: "CommandOrControl+Alt+Up",
        .opacityDown: "CommandOrControl+Alt+Down",
        .toggleAlwaysOnTop: "CommandOrControl+Alt+T",
        .moveWindowLeft: "CommandOrControl+num4",
        .moveWindowUp: "CommandOrControl+num8",
        .moveWindowRight: "CommandOrControl+num6",
        .moveWindowDown: "CommandOrControl+num2",
        .resizeWider: "CommandOrControl+Alt+num6",
        .resizeNarrower: "CommandOrControl+Alt+num4",
        .resizeTaller: "CommandOrControl+Alt+num8",
        .resizeShorter: "CommandOrControl+Alt+num2",
        .toggleSidebar: "CommandOrControl+Shift+S",
        .toggleRemoteControl: "CommandOrControl+Alt+R",
        .quitApp: "CommandOrControl+Q",
        .toggleAudioAuto: "CommandOrControl+Alt+A",
        .listenStartStop: "CommandOrControl+Alt+L",
        .listenOff: "CommandOrControl+Alt+Shift+L",
        .clearAudioCache: "CommandOrControl+Alt+Backspace",
        .cycleModel: "CommandOrControl+Alt+Right",
        .cycleEffort: "CommandOrControl+Alt+E",
        .sendMessage: "CommandOrControl+Shift+Enter",
        .newChat: "CommandOrControl+Shift+N",
        .toggleMermaidMode: "CommandOrControl+Shift+M",
        .screenshotDesktop: "CommandOrControl+Alt+3",
        .screenshotRegion: "CommandOrControl+Alt+4"
    ]

    static func normalize(_ input: HotkeyMap?) -> HotkeyMap {
        var next = defaults
        guard let input else { return next }
        for item in items {
            if let value = input[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                next[item.id] = value
            }
        }
        return next
    }

    static func displayLabel(for accelerator: String) -> String {
        accelerator
            .replacingOccurrences(of: "CommandOrControl", with: "⌘")
            .replacingOccurrences(of: "Command", with: "⌘")
            .replacingOccurrences(of: "Control", with: "⌃")
            .replacingOccurrences(of: "Alt", with: "⌥")
            .replacingOccurrences(of: "Shift", with: "⇧")
            .replacingOccurrences(of: "+", with: " ")
    }
}
