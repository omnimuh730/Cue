import Foundation

nonisolated enum SystemInstruction {
    static let defaultText =
        "You are a helpful, accurate, and concise assistant. Use Markdown when it improves readability."

    static let webSearchHint =
        "When the user asks about current events, weather, prices, or other time-sensitive facts, use web search to verify before answering."

    static let maxCharacters = 8_000

    static func normalize(_ value: String?) -> String {
        String((value ?? "").prefix(maxCharacters))
    }

    /// Global instruction, then the web-search hint, then the project's instructions and knowledge.
    /// The Responses API does not carry `instructions` across `previous_response_id`, so the full
    /// block is sent on every turn; `prompt_cache_key` keeps the repeated prefix cheap.
    static func buildResponseInstructions(_ systemInstruction: String?, webSearchEnabled: Bool, project: ProjectContext? = nil) -> String {
        let custom = (systemInstruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var text = custom.isEmpty ? defaultText : custom
        if webSearchEnabled, !text.lowercased().contains("web search") {
            text += "\n\n\(webSearchHint)"
        }
        if let block = project?.promptBlock() {
            text += "\n\n\(block)"
        }
        return text
    }
}
