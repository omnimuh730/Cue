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

nonisolated enum AttachmentKind: String, Codable, Sendable {
    /// Raster image sent as `input_image`.
    case image
    /// PDF sent natively as `input_file` (OpenAI); Codex chats get the extracted `text`.
    case pdf
    /// Office document (docx / xlsx / pptx / rtf) reduced to extracted `text`.
    case document
    /// Plain text or source file; `text` is the file contents.
    case text
    /// Skill body attached from the `/` picker; `text` is the skill Markdown.
    case skill
    /// A per-message tool switched on from the `@` picker (`name` is the `ComposerTool`); no payload.
    case tool
}

nonisolated struct MessageAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var kind: AttachmentKind
    var mimeType: String
    var name: String
    /// Base64 data URL for `.image` and `.pdf`; empty for text-only kinds.
    var dataURL: String
    /// Extracted or literal text for every kind but `.image`.
    var text: String?
    var byteCount: Int?
    /// True when `text` was cut at the importer's size cap.
    var truncated: Bool

    init(
        id: String = UUID().uuidString,
        kind: AttachmentKind = .image,
        mimeType: String,
        name: String,
        dataURL: String = "",
        text: String? = nil,
        byteCount: Int? = nil,
        truncated: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.name = name
        self.dataURL = dataURL
        self.text = text
        self.byteCount = byteCount
        self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, mimeType, name, dataURL, text, byteCount, truncated
    }

    /// Rows written before document attachments existed carry only image fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(AttachmentKind.self, forKey: .kind) ?? .image
        mimeType = try container.decode(String.self, forKey: .mimeType)
        name = try container.decode(String.self, forKey: .name)
        dataURL = try container.decodeIfPresent(String.self, forKey: .dataURL) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
    }

    var isImage: Bool { kind == .image }

    /// Text the model should read for this attachment (nil for images).
    var promptText: String? {
        guard kind != .image else { return nil }
        return text
    }
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

/// A web source the model cited, from a `url_citation` annotation.
nonisolated struct Citation: Codable, Equatable, Hashable, Sendable {
    var url: String
    var title: String
    /// Character span of the answer the citation supports, when the API gave one.
    var startIndex: Int?
    var endIndex: Int?

    /// Host without a leading "www.", for the chip.
    var host: String {
        let host = URL(string: url)?.host ?? url
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The title, or the host when the API sent none.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? host : trimmed
    }
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
    var citations: [Citation] = []

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
    /// Stable per-thread key so OpenAI routes every turn to the same prompt-cache shard.
    var promptCacheKey: String? = nil
    /// Instructions and knowledge of the project this thread belongs to, if any.
    var project: ProjectContext? = nil
    /// Whether this turn may call web search: the global setting, or an `@web_search` chip on
    /// the newest user message.
    var webSearch = false
}

/// Composer primary action. A live turn never blocks send: typed follow-ups interrupt immediately.
nonisolated enum ComposerPrimaryAction: Equatable, Sendable {
    case send
    case stop

    static func resolve(isStreaming: Bool, hasPayload: Bool) -> ComposerPrimaryAction {
        isStreaming && !hasPayload ? .stop : .send
    }
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
            "Type a message or attach a file first."
        case .transport(let message):
            message
        }
    }
}
