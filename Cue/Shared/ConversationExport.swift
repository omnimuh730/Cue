import AppKit
import Foundation
import UniformTypeIdentifiers

/// A chat as a Markdown document: title, then each turn under its own heading with attachments
/// listed by name and the sources a reply cited.
nonisolated enum ConversationExport {
    static func markdown(title: String, turns: [ChatTurn]) -> String {
        var lines: [String] = ["# \(title)", ""]
        for turn in turns where turn.role == .user || turn.role == .assistant {
            lines.append("## \(turn.role == .user ? "User" : "Assistant")")
            lines.append("")
            let files = turn.attachments.filter { $0.kind != .tool }.map(\.name)
            if !files.isEmpty {
                lines.append("_Attached: \(files.joined(separator: ", "))_")
                lines.append("")
            }
            lines.append(turn.content.trimmingCharacters(in: .whitespacesAndNewlines))
            if !turn.citations.isEmpty {
                lines.append("")
                lines.append("Sources:")
                for (index, citation) in turn.citations.enumerated() {
                    lines.append("\(index + 1). [\(citation.displayTitle)](\(citation.url))")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// A file name Finder will take: the title with path separators and control characters out.
    static func fileName(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Chat" : String(cleaned.prefix(60))) + ".md"
    }
}

extension ConversationExport {
    @MainActor
    static func save(_ conversation: Conversation) {
        let text = markdown(title: conversation.title, turns: conversation.messages.sorted { $0.createdAt < $1.createdAt }.map { $0.asTurn() })
        let panel = NSSavePanel()
        panel.title = "Save chat as Markdown"
        panel.nameFieldStringValue = fileName(for: conversation.title)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
