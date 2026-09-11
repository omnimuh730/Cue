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

    static func buildResponseInstructions(_ systemInstruction: String?, webSearchEnabled: Bool) -> String {
        let custom = (systemInstruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = custom.isEmpty ? defaultText : custom
        guard webSearchEnabled else { return base }
        if base.lowercased().contains("web search") { return base }
        return "\(base)\n\n\(webSearchHint)"
    }
}
