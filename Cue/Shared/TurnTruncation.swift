import Foundation

/// Which turns survive when a thread is cut at a message: everything up to that message,
/// including it or not. Pure so regenerate / edit / delete-from-here share one tested rule.
nonisolated enum TurnTruncation {
    /// Turns to keep when cutting the thread at `id`. `inclusive` keeps `id` itself (edit and
    /// regenerate keep the user turn they restart from); exclusive drops it (delete from here).
    /// An unknown `id` keeps everything, so a stale action never empties a thread.
    static func keep<T, ID: Equatable>(_ turns: [T], at id: ID, inclusive: Bool, key: (T) -> ID) -> [T] {
        guard let index = turns.firstIndex(where: { key($0) == id }) else { return turns }
        return Array(turns.prefix(inclusive ? index + 1 : index))
    }

    /// The user turn an assistant reply answers: the nearest user turn at or before it.
    static func promptTurn<T, ID: Equatable>(for id: ID, in turns: [T], key: (T) -> ID, isUser: (T) -> Bool) -> T? {
        guard let index = turns.firstIndex(where: { key($0) == id }) else { return nil }
        return turns[...index].last(where: isUser)
    }
}

/// A transient message at the top of the window, optionally with one action ("Undo").
struct Notice: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var actionLabel: String?
    var action: (() -> Void)?
    /// Seconds before the notice clears itself; nil keeps it until tapped.
    var autoDismiss: TimeInterval?

    static func == (lhs: Notice, rhs: Notice) -> Bool { lhs.id == rhs.id }
}

/// Sidebar order: pinned chats first (newest pin on top), then everything by last activity.
nonisolated enum ConversationOrder {
    static func sorted<T>(_ chats: [T], pinnedAt: (T) -> Date?, updatedAt: (T) -> Date) -> [T] {
        chats.sorted { a, b in
            switch (pinnedAt(a), pinnedAt(b)) {
            case let (pa?, pb?): return pa > pb
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return updatedAt(a) > updatedAt(b)
            }
        }
    }
}

extension ConversationOrder {
    static func sorted(_ chats: [Conversation]) -> [Conversation] {
        sorted(chats, pinnedAt: \.pinnedAt, updatedAt: \.updatedAt)
    }
}
