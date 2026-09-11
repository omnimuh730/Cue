import SwiftUI

struct MarkdownMessageView: View {
    var text: String
    var mermaidAsCode: Bool
    /// While the turn is still streaming, Mermaid fences stay as source (the fence may be incomplete).
    var streaming: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlocks.split(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let value):
                    Text(parse(value))
                        .font(.system(size: 15.5))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                case .heading(let level, let value):
                    Text(parse(value))
                        .font(.system(size: headingSize(level), weight: .semibold))
                        .padding(.top, level <= 2 ? 6 : 2)
                        .textSelection(.enabled)
                case .code(_, let value):
                    FencedCodeView(source: value)
                case .mermaid(let value):
                    if mermaidAsCode || streaming {
                        MermaidSourceView(source: value)
                    } else {
                        MermaidBlockView(source: value)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 22
        case 2: 19
        case 3: 17
        default: 15.5
        }
    }

    private func parse(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}

/// Monospace fence body that wraps inside the reading column instead of scrolling sideways.
struct FencedCodeView: View {
    var source: String

    var body: some View {
        Text(source)
            .font(.system(size: 13, design: .monospaced))
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

nonisolated enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, String)
    case code(language: String, String)
    case mermaid(String)
}

/// Splits assistant Markdown into fenced code, Mermaid, heading, and paragraph blocks.
/// Inline formatting inside paragraphs is left to `AttributedString(markdown:)`.
nonisolated enum MarkdownBlocks {
    static func split(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: (language: String, lines: [String])?

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraph = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var open = fence {
                if trimmed.hasPrefix("```") {
                    blocks.append(fenceBlock(open))
                    fence = nil
                } else {
                    open.lines.append(line)
                    fence = open
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                fence = (language, [])
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, heading.text))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }

        if let open = fence {
            blocks.append(fenceBlock(open))
        }
        flushParagraph()
        return blocks
    }

    private static func fenceBlock(_ fence: (language: String, lines: [String])) -> MarkdownBlock {
        let body = fence.lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        if fence.language == "mermaid" { return .mermaid(body) }
        return .code(language: fence.language, body)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        let text = line[index...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }
}
