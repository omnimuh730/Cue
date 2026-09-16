import Foundation

/// Maps `codex exec --experimental-json` JSONL events onto Cue's chat stream contract.
/// Mirrors Halo's `CodexStreamMapper`; kept as a plain class so it is unit-testable.
nonisolated final class CodexEventMapper {
    private(set) var threadID: String?
    private(set) var firstTokenAt: Date?
    /// Most recent non-fatal error item (transport fallback, tool failure). Surfaced only if the
    /// turn ends without any agent text.
    private(set) var lastItemError: String?
    var hasAgentText: Bool { !lastAgentText.isEmpty }
    private var lastAgentText = ""
    private var lastStatus = ""
    private var emittedUsage = false
    private let model: ModelID
    private let effort: ReasoningEffort
    private let startedAt: Date

    init(model: ModelID, effort: ReasoningEffort, startedAt: Date = .now, threadID: String? = nil) {
        self.model = model
        self.effort = effort
        self.startedAt = startedAt
        self.threadID = threadID
    }

    nonisolated enum Failure: Error, Equatable {
        case codex(String)

        var message: String {
            switch self {
            case .codex(let text): text
            }
        }
    }

    func consume(_ event: [String: Any]) throws(Failure) -> [ChatStreamEvent] {
        guard let type = event["type"] as? String else { return [] }
        switch type {
        case "thread.started":
            if let id = event["thread_id"] as? String, !id.isEmpty { threadID = id }
            return [.status("Reading project…")]
        case "error":
            // The CLI reuses the stream error for retry notices; only `turn.failed` is terminal.
            let message = (event["message"] as? String).nonEmpty ?? "Codex failed."
            if message.hasPrefix("Reconnecting") {
                return emitStatus("Reconnecting…")
            }
            throw .codex(message)
        case "turn.failed":
            let error = event["error"] as? [String: Any]
            throw .codex((error?["message"] as? String).nonEmpty ?? "Codex failed.")
        case "item.started", "item.updated", "item.completed":
            guard let item = event["item"] as? [String: Any], let itemType = item["type"] as? String else { return [] }
            if itemType == "error" {
                // Non-fatal per the SDK contract (e.g. "Falling back from WebSockets to HTTPS").
                let message = (item["message"] as? String).nonEmpty ?? "Codex reported a problem."
                lastItemError = message
                return emitStatus(String(message.split(separator: ".").first ?? "Retrying…"))
            }
            if itemType == "agent_message" {
                if type == "item.started" { return [] }
                let text = item["text"] as? String ?? ""
                let delta = text.hasPrefix(lastAgentText) ? String(text.dropFirst(lastAgentText.count)) : text
                lastAgentText = text
                guard !delta.isEmpty else { return [] }
                if firstTokenAt == nil { firstTokenAt = .now }
                return [.delta(delta)]
            }
            guard let status = Self.status(for: item) else { return [] }
            return emitStatus(status)
        case "turn.completed":
            guard !emittedUsage, let raw = event["usage"] as? [String: Any] else { return [] }
            let usage = TokenUsage(
                inputTokens: raw["input_tokens"] as? Int ?? 0,
                outputTokens: raw["output_tokens"] as? Int ?? 0,
                cachedInputTokens: raw["cached_input_tokens"] as? Int ?? 0,
                cacheWriteTokens: raw["cache_write_input_tokens"] as? Int ?? 0,
                reasoningTokens: raw["reasoning_output_tokens"] as? Int ?? 0
            )
            guard usage.inputTokens > 0 || usage.outputTokens > 0 else { return [] }
            emittedUsage = true
            let estimate = Pricing.estimateTurnCost(model: model, usage: usage, webSearchCalls: 0)
            return [.usage(
                usage,
                costUsd: estimate.costUsd,
                model: model,
                effort: effort,
                webSearchCalls: 0,
                breakdown: estimate.breakdown
            )]
        default:
            return []
        }
    }

    private func emitStatus(_ status: String) -> [ChatStreamEvent] {
        // Once text is flowing, progress lines would only flicker under the answer.
        guard lastAgentText.isEmpty, status != lastStatus else { return [] }
        lastStatus = status
        return [.status(status)]
    }

    func done() -> ChatStreamEvent {
        let finishedAt = Date()
        return .done(
            timing: ResponseTiming(
                timeToFirstTokenMs: max(0, (firstTokenAt ?? finishedAt).timeIntervalSince(startedAt) * 1000),
                totalMs: max(0, finishedAt.timeIntervalSince(startedAt) * 1000)
            ),
            responseID: nil,
            codexThreadID: threadID
        )
    }

    /// Human-readable progress line for a thread item, or nil for items with nothing to show.
    static func status(for item: [String: Any]) -> String? {
        switch item["type"] as? String {
        case "command_execution":
            let command = (item["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if command.isEmpty { return "Reading files…" }
            let short = shorten(command)
            let verb = command.split(separator: " ", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
            switch verb {
            case "rg", "grep", "ag", "ack": return "Searching \(short)"
            case "ls", "find", "tree", "fd": return "Listing \(short)"
            case "git": return "Git \(short)"
            case "cat", "head", "tail", "sed", "bat", "less": return "Reading files…"
            default: return "Running \(short)"
            }
        case "web_search":
            if let query = (item["query"] as? String).nonEmpty { return "Searching \(query)" }
            return "Searching the web…"
        case "mcp_tool_call":
            if let tool = (item["tool"] as? String).nonEmpty { return "Using \(tool)" }
            return "Using a tool…"
        case "todo_list": return "Planning…"
        case "file_change": return "Reviewing file changes…"
        case "reasoning": return "Thinking…"
        default: return nil
        }
    }

    private static func shorten(_ command: String) -> String {
        let compact = command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if compact.count <= 64 { return compact }
        return String(compact.prefix(63)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

nonisolated enum CodexPrompt {
    /// Codex accepts `minimal…xhigh`; Cue's `none` and `max` map to the nearest ends.
    static func reasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none: "minimal"
        case .max: "xhigh"
        case .low, .medium, .high, .xhigh: effort.rawValue
        }
    }

    /// The Codex thread carries history, so each turn sends only the newest user message,
    /// optionally preceded by the project map catalog and the text of any attached files.
    static func build(messages: [ChatRequestMessage], catalog: String?, project: ProjectContext? = nil, webSearch: Bool = false) -> String {
        let last = messages.last { $0.role == .user }
        var user = last.flatMap { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.content }
            ?? (last?.attachments.isEmpty == false ? "Please read the attached files." : "Please continue from the current project context.")
        user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []
        if let block = project?.promptBlock() {
            sections.append(block)
        }
        if let trimmed = catalog?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            sections.append("Project map catalog (use this to locate files before searching the tree):\n\n\(trimmed)")
        }
        if let last, let attached = AttachmentPrompt.text(for: last.attachments, includePDFText: true) {
            sections.append(attached)
        }
        if webSearch {
            sections.append("Use web search for this question and name the sources you relied on.")
        }
        guard !sections.isEmpty else { return user }
        return sections.joined(separator: "\n\n") + "\n\nUser question:\n\(user)"
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return self
    }
}
