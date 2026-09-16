import Foundation

/// Per-message tools the user can switch on from the composer by typing `@name`, the way `/`
/// attaches a skill. One entry today; the catalog exists so `@` has somewhere to grow.
nonisolated enum ComposerTool: String, CaseIterable, Sendable, Identifiable {
    case webSearch = "web_search"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .webSearch: "Web search"
        }
    }

    var symbol: String {
        switch self {
        case .webSearch: "globe"
        }
    }

    var description: String {
        switch self {
        case .webSearch: "Search the web for this message; sources appear under the answer."
        }
    }

    /// The chip that marks a message as using this tool. It carries no payload; the backends
    /// read it as a flag.
    var attachment: MessageAttachment {
        MessageAttachment(kind: .tool, mimeType: "application/x-cue-tool", name: rawValue, text: nil, byteCount: nil)
    }

    /// Whether a message's attachments ask for this tool.
    func isRequested(in attachments: [MessageAttachment]) -> Bool {
        attachments.contains { $0.kind == .tool && $0.name == rawValue }
    }

    static func named(_ name: String) -> ComposerTool? {
        ComposerTool(rawValue: name)
    }
}

/// `@` mentions in the draft. Unlike `/`, which only counts at the start, `@` can sit anywhere:
/// "what's the weather in Tokyo @web" is how people type it.
nonisolated enum MentionInvocation {
    /// The partial name after the `@` the user is typing, or nil when no mention is open. The
    /// `@` must start a word (start of draft or after whitespace) and the token must still be
    /// unbroken by whitespace, so an email address or a finished mention does not reopen it.
    static func query(in draft: String) -> String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        if at > draft.startIndex {
            let before = draft[draft.index(before: at)]
            guard before.isWhitespace || before.isNewline else { return nil }
        }
        let token = draft[draft.index(after: at)...]
        guard !token.contains(where: \.isWhitespace) else { return nil }
        return String(token)
    }

    /// The draft with the open `@query` token removed (and the space before it, if any).
    static func removingQuery(from draft: String) -> String {
        guard let at = draft.lastIndex(of: "@"), query(in: draft) != nil else { return draft }
        var result = String(draft[..<at])
        while result.last == " " { result.removeLast() }
        return result
    }

    static func filter(_ tools: [ComposerTool], query: String) -> [ComposerTool] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return tools }
        return tools.filter {
            $0.rawValue.hasPrefix(needle)
                || $0.rawValue.replacingOccurrences(of: "_", with: "").hasPrefix(needle.replacingOccurrences(of: "_", with: ""))
                || $0.label.lowercased().hasPrefix(needle)
        }
    }
}
