import Foundation

/// Everything the thread info sheet shows, computed once from the turns so the view stays dumb.
nonisolated struct ThreadSummary: Equatable, Sendable {
    nonisolated struct TurnRow: Equatable, Sendable, Identifiable {
        var id: UUID
        var index: Int
        var model: ModelID?
        var effort: ReasoningEffort?
        var costUsd: Double
        var inputTokens: Int
        var cachedInputTokens: Int
        var outputTokens: Int
        var reasoningTokens: Int
        var timeToFirstTokenMs: Double?
        var totalMs: Double?
        var webSearchCalls: Int
        var status: MessageStatus?
    }

    var userMessages: Int
    var assistantMessages: Int
    var totalCostUsd: Double
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var webSearchCalls: Int
    var models: [ModelID]
    var averageFirstTokenMs: Double?
    var averageTotalMs: Double?
    var turns: [TurnRow]

    /// Share of prompt tokens served from OpenAI's prompt cache, 0…1.
    var cacheHitRatio: Double? {
        guard inputTokens > 0 else { return nil }
        return Double(cachedInputTokens) / Double(inputTokens)
    }

    static func build(from turns: [ChatTurn]) -> ThreadSummary {
        var rows: [TurnRow] = []
        var cost = 0.0
        var input = 0, cached = 0, output = 0, reasoning = 0, searches = 0
        var models: [ModelID] = []
        var firstToken: [Double] = []
        var totals: [Double] = []
        var users = 0

        for turn in turns {
            if turn.role == .user { users += 1; continue }
            guard turn.role == .assistant else { continue }
            let usage = turn.usage ?? .zero
            cost += turn.costUsd ?? 0
            input += usage.inputTokens
            cached += usage.cachedInputTokens
            output += usage.outputTokens
            reasoning += usage.reasoningTokens
            searches += turn.webSearchCalls ?? 0
            if let model = turn.model, !models.contains(model) { models.append(model) }
            if let timing = turn.timing {
                firstToken.append(timing.timeToFirstTokenMs)
                totals.append(timing.totalMs)
            }
            rows.append(TurnRow(
                id: turn.id,
                index: rows.count + 1,
                model: turn.model,
                effort: turn.reasoningEffort,
                costUsd: turn.costUsd ?? 0,
                inputTokens: usage.inputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                outputTokens: usage.outputTokens,
                reasoningTokens: usage.reasoningTokens,
                timeToFirstTokenMs: turn.timing?.timeToFirstTokenMs,
                totalMs: turn.timing?.totalMs,
                webSearchCalls: turn.webSearchCalls ?? 0,
                status: turn.status
            ))
        }

        return ThreadSummary(
            userMessages: users,
            assistantMessages: rows.count,
            totalCostUsd: cost,
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningTokens: reasoning,
            webSearchCalls: searches,
            models: models,
            averageFirstTokenMs: firstToken.isEmpty ? nil : firstToken.reduce(0, +) / Double(firstToken.count),
            averageTotalMs: totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count),
            turns: rows
        )
    }

    static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 10_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return value.formatted()
    }

    static func formatMs(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1fs", value / 1000) : "\(Int(value.rounded()))ms"
    }
}
