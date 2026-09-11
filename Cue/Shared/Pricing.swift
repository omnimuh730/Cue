import Foundation

nonisolated struct TokenRates: Equatable, Sendable {
    var inputPerMillion: Double
    var cachedInputPerMillion: Double
    var cacheWritePerMillion: Double
    var outputPerMillion: Double
}

nonisolated struct ModelPricing: Equatable, Sendable {
    var standard: TokenRates
    var longContext: TokenRates?
}

nonisolated struct TurnCostEstimate: Equatable, Sendable {
    var costUsd: Double
    var breakdown: CostBreakdown
    var usedLongContext: Bool
}

nonisolated enum Pricing {
    static let longContextInputThreshold = 272_000
    static let webSearchCostPerCallUsd = 0.01

    static let modelPricing: [ModelID: ModelPricing] = [
        .sol: ModelPricing(
            standard: TokenRates(inputPerMillion: 5, cachedInputPerMillion: 0.5, cacheWritePerMillion: 6.25, outputPerMillion: 30),
            longContext: TokenRates(inputPerMillion: 10, cachedInputPerMillion: 1, cacheWritePerMillion: 12.5, outputPerMillion: 45)
        ),
        .terra: ModelPricing(
            standard: TokenRates(inputPerMillion: 2, cachedInputPerMillion: 0.2, cacheWritePerMillion: 2.5, outputPerMillion: 12),
            longContext: TokenRates(inputPerMillion: 4, cachedInputPerMillion: 0.4, cacheWritePerMillion: 5, outputPerMillion: 18)
        ),
        .luna: ModelPricing(
            standard: TokenRates(inputPerMillion: 0.2, cachedInputPerMillion: 0.02, cacheWritePerMillion: 0.25, outputPerMillion: 1.2),
            longContext: TokenRates(inputPerMillion: 0.4, cachedInputPerMillion: 0.04, cacheWritePerMillion: 0.5, outputPerMillion: 1.8)
        ),
        .mini: ModelPricing(
            standard: TokenRates(inputPerMillion: 0.75, cachedInputPerMillion: 0.075, cacheWritePerMillion: 0, outputPerMillion: 4.5),
            longContext: nil
        )
    ]

    static func estimateTurnCost(model: ModelID, usage: TokenUsage, webSearchCalls: Int = 0) -> TurnCostEstimate {
        let cachedInputTokens = max(0, min(usage.cachedInputTokens, usage.inputTokens))
        let cacheWriteTokens = max(0, usage.cacheWriteTokens)
        let uncachedInputTokens = max(0, usage.inputTokens - cachedInputTokens)
        let outputTokens = max(0, usage.outputTokens)
        let calls = max(0, webSearchCalls)
        let rates = rates(for: model, inputTokens: usage.inputTokens)
        let inputUsd = usdFromTokens(uncachedInputTokens, rates.inputPerMillion)
        let cachedUsd = usdFromTokens(cachedInputTokens, rates.cachedInputPerMillion)
        let cacheWriteUsd = usdFromTokens(cacheWriteTokens, rates.cacheWritePerMillion)
        let outputUsd = usdFromTokens(outputTokens, rates.outputPerMillion)
        let webSearchUsd = Double(calls) * webSearchCostPerCallUsd
        let totalUsd = inputUsd + cachedUsd + cacheWriteUsd + outputUsd + webSearchUsd
        return TurnCostEstimate(
            costUsd: totalUsd,
            breakdown: CostBreakdown(
                inputUsd: inputUsd,
                cachedUsd: cachedUsd,
                cacheWriteUsd: cacheWriteUsd,
                outputUsd: outputUsd,
                webSearchUsd: webSearchUsd,
                totalUsd: totalUsd
            ),
            usedLongContext: rates.usedLongContext
        )
    }

    static func formatUsd(_ amount: Double) -> String {
        guard amount.isFinite, amount > 0 else { return "$0.00" }
        if amount < 0.01 { return String(format: "$%.4f", amount) }
        if amount < 1 {
            let text = String(format: "$%.3f", amount)
            return text.hasSuffix("0") ? String(text.dropLast()) : text
        }
        return String(format: "$%.2f", amount)
    }

    static func formatSeconds(_ ms: Double) -> String {
        guard ms.isFinite, ms >= 0 else { return "—" }
        return String(format: "%.3fs", ms / 1000)
    }

    static func formatLatencyPair(timeToFirstTokenMs: Double, totalMs: Double) -> String {
        "\(formatSeconds(timeToFirstTokenMs))/\(formatSeconds(totalMs))"
    }

    private struct Rates {
        var inputPerMillion: Double
        var cachedInputPerMillion: Double
        var cacheWritePerMillion: Double
        var outputPerMillion: Double
        var usedLongContext: Bool
    }

    private static func rates(for model: ModelID, inputTokens: Int) -> Rates {
        let pricing = modelPricing[model] ?? modelPricing[.sol] ?? ModelPricing(
            standard: TokenRates(inputPerMillion: 5, cachedInputPerMillion: 0.5, cacheWritePerMillion: 6.25, outputPerMillion: 30),
            longContext: nil
        )
        if let long = pricing.longContext, inputTokens > longContextInputThreshold {
            return Rates(
                inputPerMillion: long.inputPerMillion,
                cachedInputPerMillion: long.cachedInputPerMillion,
                cacheWritePerMillion: long.cacheWritePerMillion,
                outputPerMillion: long.outputPerMillion,
                usedLongContext: true
            )
        }
        return Rates(
            inputPerMillion: pricing.standard.inputPerMillion,
            cachedInputPerMillion: pricing.standard.cachedInputPerMillion,
            cacheWritePerMillion: pricing.standard.cacheWritePerMillion,
            outputPerMillion: pricing.standard.outputPerMillion,
            usedLongContext: false
        )
    }

    private static func usdFromTokens(_ tokens: Int, _ perMillion: Double) -> Double {
        (Double(tokens) / 1_000_000) * perMillion
    }
}
