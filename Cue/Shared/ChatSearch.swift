import Foundation

/// One search result: a chat, and the message that matched when the hit is in a message
/// rather than the title.
nonisolated struct SearchHit<Chat, Message>: Identifiable {
    var id: String
    var chat: Chat
    var message: Message?
    /// A short excerpt around the first match, with the matched range inside it.
    var snippet: String
    var matchRange: Range<String.Index>?
}

/// Case-insensitive chat search. Title hits come first (one per chat), then message hits in
/// thread order, each with an excerpt around the first occurrence.
nonisolated enum ChatSearch {
    static let snippetRadius = 60

    static func hits<Chat, Message>(
        query: String,
        chats: [Chat],
        chatID: (Chat) -> String,
        title: (Chat) -> String,
        messages: (Chat) -> [Message],
        messageID: (Message) -> String,
        content: (Message) -> String
    ) -> [SearchHit<Chat, Message>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return chats.map { SearchHit(id: chatID($0), chat: $0, message: nil, snippet: "", matchRange: nil) }
        }
        var titleHits: [SearchHit<Chat, Message>] = []
        var messageHits: [SearchHit<Chat, Message>] = []
        for chat in chats {
            let chatTitle = title(chat)
            if let range = chatTitle.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
                titleHits.append(SearchHit(id: chatID(chat), chat: chat, message: nil, snippet: chatTitle, matchRange: range))
            }
            for message in messages(chat) {
                let text = content(message)
                guard let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let excerpt = snippet(of: text, around: range)
                messageHits.append(SearchHit(
                    id: chatID(chat) + "/" + messageID(message),
                    chat: chat,
                    message: message,
                    snippet: excerpt.text,
                    matchRange: excerpt.match
                ))
            }
        }
        return titleHits + messageHits
    }

    /// `snippetRadius` characters either side of the match, on one line, with ellipses where cut.
    static func snippet(of text: String, around match: Range<String.Index>) -> (text: String, match: Range<String.Index>?) {
        let start = text.index(match.lowerBound, offsetBy: -snippetRadius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: snippetRadius, limitedBy: text.endIndex) ?? text.endIndex
        var excerpt = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        let matchOffset = text.distance(from: start, to: match.lowerBound)
        let matchLength = text.distance(from: match.lowerBound, to: match.upperBound)
        var prefixCount = 0
        if start > text.startIndex {
            excerpt = "…" + excerpt
            prefixCount = 1
        }
        if end < text.endIndex { excerpt += "…" }
        guard let lower = excerpt.index(excerpt.startIndex, offsetBy: matchOffset + prefixCount, limitedBy: excerpt.endIndex),
              let upper = excerpt.index(lower, offsetBy: matchLength, limitedBy: excerpt.endIndex)
        else { return (excerpt, nil) }
        return (excerpt, lower..<upper)
    }
}
