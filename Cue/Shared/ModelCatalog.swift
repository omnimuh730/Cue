import Foundation

nonisolated enum ModelID: String, CaseIterable, Sendable, Identifiable {
    case astra = "gpt-6-astra"
    case gpt6Sol = "gpt-6-sol"
    case gpt6Luna = "gpt-6-luna"
    case sol = "gpt-5.6-sol"
    case terra = "gpt-5.6-terra"
    case luna = "gpt-5.6-luna"

    var id: String { rawValue }
}

extension ModelID: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "gpt-5.4-mini":
            self = .gpt6Luna
        default:
            self = ModelID(rawValue: raw) ?? .sol
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated enum ReasoningEffort: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }
}

nonisolated struct ModelDefinition: Equatable, Sendable, Identifiable {
    var id: ModelID
    var label: String
    var shortLabel: String
    var description: String
    var group: String
    var supportedEfforts: [ReasoningEffort]
}

nonisolated struct EffortDefinition: Equatable, Sendable, Identifiable {
    var id: ReasoningEffort
    var label: String
    var shortLabel: String
    var description: String
}

nonisolated enum ModelCatalog {
    static let reasoningEfforts: [EffortDefinition] = [
        .init(id: .none, label: "Off", shortLabel: "Off", description: "Fastest response with no extra reasoning"),
        .init(id: .low, label: "Light", shortLabel: "Light", description: "Quick reasoning for well-scoped questions"),
        .init(id: .medium, label: "Medium", shortLabel: "Medium", description: "Balanced speed and depth"),
        .init(id: .high, label: "High", shortLabel: "High", description: "More planning for difficult work"),
        .init(id: .xhigh, label: "Extra High", shortLabel: "Extra High", description: "Deep reasoning for complex tasks"),
        .init(id: .max, label: "Max", shortLabel: "Max", description: "Most reasoning for the hardest tasks")
    ]

    private static let fullEffort: [ReasoningEffort] = [.none, .low, .medium, .high, .xhigh, .max]
    /// Astra rejects `reasoning.effort: none` with HTTP 400.
    private static let astraEffort: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max]

    static let models: [ModelDefinition] = [
        .init(
            id: .astra,
            label: "GPT-6 Astra",
            shortLabel: "6 Astra",
            description: "Most capable model for the hardest end-to-end work",
            group: "GPT-6",
            supportedEfforts: astraEffort
        ),
        .init(
            id: .gpt6Sol,
            label: "GPT-6 Sol",
            shortLabel: "6 Sol",
            description: "Complex coding and agentic workflows",
            group: "GPT-6",
            supportedEfforts: fullEffort
        ),
        .init(
            id: .gpt6Luna,
            label: "GPT-6 Luna",
            shortLabel: "6 Luna",
            description: "Efficient for focused, high-volume tasks",
            group: "GPT-6",
            supportedEfforts: fullEffort
        ),
        .init(
            id: .sol,
            label: "GPT-5.6 Sol",
            shortLabel: "5.6 Sol",
            description: "Frontier capability for complex work",
            group: "GPT-5.6",
            supportedEfforts: fullEffort
        ),
        .init(
            id: .terra,
            label: "GPT-5.6 Terra",
            shortLabel: "5.6 Terra",
            description: "Balanced intelligence and cost",
            group: "GPT-5.6",
            supportedEfforts: fullEffort
        ),
        .init(
            id: .luna,
            label: "GPT-5.6 Luna",
            shortLabel: "5.6 Luna",
            description: "Efficient for fast, high-volume work",
            group: "GPT-5.6",
            supportedEfforts: fullEffort
        )
    ]

    static let `default`: ModelID = .sol
    static let defaultEffort: ReasoningEffort = .low

    static var groupedModels: [(group: String, models: [ModelDefinition])] {
        var groups: [(String, [ModelDefinition])] = []
        for model in models {
            if let last = groups.last, last.0 == model.group {
                groups[groups.count - 1].1.append(model)
            } else {
                groups.append((model.group, [model]))
            }
        }
        return groups.map { (group: $0.0, models: $0.1) }
    }

    static func definition(for id: ModelID) -> ModelDefinition {
        models.first { $0.id == id } ?? models[0]
    }

    static func definition(for effort: ReasoningEffort) -> EffortDefinition {
        reasoningEfforts.first { $0.id == effort } ?? reasoningEfforts[1]
    }

    static func normalizeEffort(_ effort: ReasoningEffort, for model: ModelID) -> ReasoningEffort {
        let supported = definition(for: model).supportedEfforts
        if supported.contains(effort) { return effort }
        guard let requested = reasoningEfforts.firstIndex(where: { $0.id == effort }) else {
            return supported[0]
        }
        var index = requested - 1
        while index >= 0 {
            let candidate = reasoningEfforts[index].id
            if supported.contains(candidate) { return candidate }
            index -= 1
        }
        return supported[0]
    }

    static func nextModel(after current: ModelID) -> ModelID {
        guard let index = models.firstIndex(where: { $0.id == current }) else { return models[0].id }
        return models[(index + 1) % models.count].id
    }

    static func nextEffort(after current: ReasoningEffort, for model: ModelID) -> ReasoningEffort {
        let supported = definition(for: model).supportedEfforts
        guard let index = supported.firstIndex(of: current) else { return supported[0] }
        return supported[(index + 1) % supported.count]
    }
}
