import Foundation
import SwiftData

@Model
final class Conversation {
    var identifier: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var totalCostUsd: Double
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalReasoningTokens: Int
    var totalWebSearchCalls: Int
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        identifier: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.identifier = identifier
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalCostUsd = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.totalReasoningTokens = 0
        self.totalWebSearchCalls = 0
        self.messages = []
    }
}

@Model
final class Message {
    var identifier: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var statusRaw: String?
    var costUsd: Double?
    var webSearchCalls: Int?
    var responseID: String?
    var modelRaw: String?
    var effortRaw: String?
    var attachmentsJSON: Data?
    var usageJSON: Data?
    var timingJSON: Data?
    var preferenceJSON: Data?
    var conversation: Conversation?

    init(
        identifier: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = .now,
        status: MessageStatus? = nil
    ) {
        self.identifier = identifier
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.statusRaw = status?.rawValue
    }

    var role: MessageRole {
        MessageRole(rawValue: roleRaw) ?? .user
    }

    var status: MessageStatus? {
        statusRaw.flatMap(MessageStatus.init(rawValue:))
    }

    func asTurn() -> ChatTurn {
        let decoder = JSONDecoder()
        return ChatTurn(
            id: identifier,
            role: role,
            content: content,
            createdAt: createdAt,
            status: status,
            attachments: decode(attachmentsJSON, as: [MessageAttachment].self, decoder: decoder) ?? [],
            usage: decode(usageJSON, as: TokenUsage.self, decoder: decoder),
            costUsd: costUsd,
            webSearchCalls: webSearchCalls,
            timing: decode(timingJSON, as: ResponseTiming.self, decoder: decoder),
            model: modelRaw.flatMap(ModelID.init(rawValue:)),
            reasoningEffort: effortRaw.flatMap(ReasoningEffort.init(rawValue:)),
            responseID: responseID,
            preferenceChange: decode(preferenceJSON, as: PreferenceChange.self, decoder: decoder)
        )
    }

    func apply(_ turn: ChatTurn) {
        identifier = turn.id
        roleRaw = turn.role.rawValue
        content = turn.content
        createdAt = turn.createdAt
        statusRaw = turn.status?.rawValue
        costUsd = turn.costUsd
        webSearchCalls = turn.webSearchCalls
        responseID = turn.responseID
        modelRaw = turn.model?.rawValue
        effortRaw = turn.reasoningEffort?.rawValue
        attachmentsJSON = encode(turn.attachments)
        usageJSON = turn.usage.flatMap(encode)
        timingJSON = turn.timing.flatMap(encode)
        preferenceJSON = turn.preferenceChange.flatMap(encode)
    }
}

private func encode<T: Encodable>(_ value: T) -> Data? {
    try? JSONEncoder().encode(value)
}

private func decode<T: Decodable>(_ data: Data?, as type: T.Type, decoder: JSONDecoder) -> T? {
    guard let data else { return nil }
    return try? decoder.decode(type, from: data)
}
