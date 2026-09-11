import Foundation

nonisolated enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case meta
}

nonisolated enum MessageStatus: String, Codable, Sendable {
    case streaming
    case complete
    case error
}

nonisolated struct MessageAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var mimeType: String
    var name: String
    var dataURL: String
}

nonisolated struct TokenUsage: Codable, Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var cachedInputTokens: Int
    var cacheWriteTokens: Int
    var reasoningTokens: Int

    static let zero = TokenUsage(
        inputTokens: 0,
        outputTokens: 0,
        cachedInputTokens: 0,
        cacheWriteTokens: 0,
        reasoningTokens: 0
    )
}

nonisolated struct CostBreakdown: Codable, Equatable, Sendable {
    var inputUsd: Double
    var cachedUsd: Double
    var cacheWriteUsd: Double
    var outputUsd: Double
    var webSearchUsd: Double
    var totalUsd: Double
}

nonisolated struct ResponseTiming: Codable, Equatable, Sendable {
    var timeToFirstTokenMs: Double
    var totalMs: Double
}

nonisolated struct ConversationUsageSummary: Codable, Equatable, Sendable {
    var totalCostUsd: Double
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalReasoningTokens: Int
    var totalWebSearchCalls: Int

    static let zero = ConversationUsageSummary(
        totalCostUsd: 0,
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalReasoningTokens: 0,
        totalWebSearchCalls: 0
    )
}

nonisolated struct PreferenceChange: Codable, Equatable, Sendable {
    var previousModel: ModelID
    var model: ModelID
    var previousEffort: ReasoningEffort
    var effort: ReasoningEffort
}

nonisolated struct ChatTurn: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var role: MessageRole
    var content: String
    var createdAt: Date
    var status: MessageStatus?
    var attachments: [MessageAttachment]
    var usage: TokenUsage?
    var costUsd: Double?
    var webSearchCalls: Int?
    var timing: ResponseTiming?
    var model: ModelID?
    var reasoningEffort: ReasoningEffort?
    var responseID: String?
    var preferenceChange: PreferenceChange?

    var isAPIMessage: Bool {
        role == .user || role == .assistant
    }
}

nonisolated struct ChatRequestMessage: Codable, Equatable, Sendable {
    var role: MessageRole
    var content: String
    var attachments: [MessageAttachment]
}

nonisolated struct ChatContinuation: Equatable, Sendable {
    var messages: [ChatRequestMessage]
    var previousResponseID: String?
    var inputMessages: [ChatRequestMessage]?
}

nonisolated enum ChatError: LocalizedError {
    case missingAPIKey
    case emptyMessage
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add an OpenAI API key in Settings to chat."
        case .emptyMessage:
            "Type a message or attach an image first."
        case .transport(let message):
            message
        }
    }
}
