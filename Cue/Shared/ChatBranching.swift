import Foundation

/// Branching for chats, borrowed from git: forking a thread at a message is `checkout -b` — the
/// turns up to that point are copied into a new branch, the original is left exactly as it was,
/// and the branch records where it was cut. Both versions live on, side by side, as tabs.
///
/// Pure, so the tree math is unit-testable: `AppSession` owns the SwiftData rows, this owns the
/// rules for what a family is, how it is ordered, and what a branch is called.
nonisolated enum ChatBranching {
    /// The branch every family starts from: the chat nothing was forked from.
    static let mainBranchName = "main"

    /// Longest passage "Add to chat" or a fork quote carries into the composer.
    static let maxQuoteCharacters = 4_000

    /// The root of `id`'s family: follow the fork links up until one has no parent. A link that
    /// points at a chat that is gone, or back into the chain, stops the walk, so a damaged tree
    /// resolves to a root instead of looping.
    static func rootID<ID: Hashable>(of id: ID, parent: (ID) -> ID?) -> ID {
        var current = id
        var seen: Set<ID> = [id]
        while let next = parent(current), !seen.contains(next) {
            seen.insert(next)
            current = next
        }
        return current
    }

    /// Every chat in `id`'s family, root first and the rest in the order they were given (the
    /// caller passes creation order, so tabs read left to right as the forks were made).
    static func family<T, ID: Hashable>(of id: ID, in chats: [T], key: (T) -> ID, parent: (T) -> ID?) -> [T] {
        let links = parentLinks(in: chats, key: key, parent: parent)
        let root = rootID(of: id, parent: { links[$0] })
        let members = chats.filter { rootID(of: key($0), parent: { links[$0] }) == root }
        guard let first = members.first(where: { key($0) == root }) else { return members }
        return [first] + members.filter { key($0) != root }
    }

    /// The branches forked directly from `id`. They inherit its own fork link when it is deleted,
    /// so a family never splits into orphans.
    static func children<T, ID: Hashable>(of id: ID, in chats: [T], parent: (T) -> ID?) -> [T] {
        chats.filter { parent($0) == id }
    }

    /// Default tab label for the branch at `index` in its family, root first: `main`, then the
    /// forks numbered in the order they were made.
    static func defaultName(index: Int) -> String {
        index <= 0 ? mainBranchName : "fork \(index)"
    }

    /// A Markdown block quote of `text`, the way "Add to chat" carries a passage into the
    /// composer. Blank lines inside the passage stay inside the quote so the model reads the
    /// whole thing as one piece, and an over-long selection is cut with an ellipsis.
    static func quote(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let clipped = trimmed.count > maxQuoteCharacters
            ? String(trimmed.prefix(maxQuoteCharacters)) + "…"
            : trimmed
        return clipped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
    }

    /// The draft after a passage is quoted into it: the quote becomes its own block under
    /// whatever was already typed, with a blank line after it for the question.
    static func appendingQuote(_ text: String, to draft: String) -> String {
        let quoted = quote(text)
        guard !quoted.isEmpty else { return draft }
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return quoted + "\n\n" }
        return typed + "\n\n" + quoted + "\n\n"
    }

    private static func parentLinks<T, ID: Hashable>(in chats: [T], key: (T) -> ID, parent: (T) -> ID?) -> [ID: ID] {
        var links: [ID: ID] = [:]
        for chat in chats {
            guard let parentID = parent(chat) else { continue }
            links[key(chat)] = parentID
        }
        return links
    }
}
