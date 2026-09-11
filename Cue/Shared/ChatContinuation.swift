import Foundation

nonisolated enum ChatContinuationBuilder {
    static func build(from turns: [ChatTurn]) -> ChatContinuation {
        let apiMessages = turns.filter(\.isAPIMessage).filter { $0.status != .error }
        let messages = toRequestMessages(apiMessages)

        var anchorIndex = -1
        var previousResponseID: String?
        for (index, message) in apiMessages.enumerated() {
            if message.role == .assistant, message.status == .complete, let responseID = message.responseID, !responseID.isEmpty {
                anchorIndex = index
                previousResponseID = responseID
            }
        }

        guard let previousResponseID, anchorIndex >= 0 else {
            return ChatContinuation(messages: messages, previousResponseID: nil, inputMessages: nil)
        }

        let suffix = Array(apiMessages.suffix(from: anchorIndex + 1))
        if suffix.isEmpty || suffix.contains(where: { $0.role == .assistant }) {
            return ChatContinuation(messages: messages, previousResponseID: nil, inputMessages: nil)
        }

        return ChatContinuation(
            messages: messages,
            previousResponseID: previousResponseID,
            inputMessages: toRequestMessages(suffix)
        )
    }

    private static func toRequestMessages(_ turns: [ChatTurn]) -> [ChatRequestMessage] {
        turns.map { turn in
            ChatRequestMessage(role: turn.role, content: turn.content, attachments: turn.attachments)
        }
    }
}
