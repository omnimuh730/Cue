import Foundation

/// Which way the transcript reads. Newest-at-bottom is the familiar chat layout; newest-at-top
/// keeps the live answer under the reader's eye without any scrolling, which is what an interview
/// prompter wants.
nonisolated enum ReadingOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case newestAtBottom
    case newestAtTop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestAtBottom: "Newest at bottom"
        case .newestAtTop: "Newest at top"
        }
    }

    var help: String {
        switch self {
        case .newestAtBottom: "Chat style. New replies land at the bottom and the transcript follows them."
        case .newestAtTop: "Prompter style. The latest exchange sits at the top; older ones stack below."
        }
    }

    /// Arranges chronological messages for display.
    ///
    /// Newest-at-top reverses *exchanges*, not messages: a question still reads above its answer,
    /// so a turn is read top-down either way. An exchange is a user message and every message that
    /// follows it until the next one from the user.
    func arrange<T>(_ chronological: [T], isUser: (T) -> Bool) -> [T] {
        switch self {
        case .newestAtBottom:
            return chronological
        case .newestAtTop:
            var exchanges: [[T]] = []
            for message in chronological {
                if isUser(message) || exchanges.isEmpty {
                    exchanges.append([message])
                } else {
                    exchanges[exchanges.count - 1].append(message)
                }
            }
            return exchanges.reversed().flatMap { $0 }
        }
    }
}
