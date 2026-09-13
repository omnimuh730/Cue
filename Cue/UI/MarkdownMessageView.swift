import SwiftUI

/// A block with its inline Markdown already parsed, ready to draw without further work.
nonisolated struct RenderedBlock: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case paragraph(AttributedString)
        case heading(level: Int, AttributedString)
        case code(String)
        case mermaid(String)
    }

    /// Position in the message; stable while streaming appends, so earlier views are reused.
    var id: Int
    var source: MarkdownBlock
    var kind: Kind
}

/// Turns Markdown into `RenderedBlock`s. Parsing is the expensive step (`AttributedString(markdown:)`),
/// so blocks whose source is unchanged from the previous pass are reused verbatim — while streaming
/// only the trailing block is ever new.
nonisolated enum MarkdownRenderer {
    static func render(_ text: String, reusing previous: [RenderedBlock]) -> [RenderedBlock] {
        var cache: [MarkdownBlock: RenderedBlock.Kind] = [:]
        for block in previous { cache[block.source] = block.kind }
        return MarkdownBlocks.split(text).enumerated().map { index, block in
            if let kind = cache[block] { return RenderedBlock(id: index, source: block, kind: kind) }
            return RenderedBlock(id: index, source: block, kind: kind(for: block))
        }
    }

    static func renderInBackground(_ text: String, reusing previous: [RenderedBlock]) async -> [RenderedBlock] {
        await Task.detached(priority: .userInitiated) { render(text, reusing: previous) }.value
    }

    private static func kind(for block: MarkdownBlock) -> RenderedBlock.Kind {
        switch block {
        case .paragraph(let value): .paragraph(parse(value))
        case .heading(let level, let value): .heading(level: level, parse(value))
        case .code(_, let value): .code(value)
        case .mermaid(let value): .mermaid(value)
        }
    }

    private static func parse(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}

/// Consecutive text blocks render as one selectable text view; Mermaid blocks break the run.
nonisolated enum MessageSegment: Identifiable, Equatable {
    case text(id: Int, blocks: [RenderedBlock])
    case mermaid(id: Int, source: String)

    var id: Int {
        switch self {
        case .text(let id, _), .mermaid(let id, _): id
        }
    }

    static func group(_ blocks: [RenderedBlock]) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var run: [RenderedBlock] = []
        func flush() {
            guard let first = run.first else { return }
            segments.append(.text(id: first.id, blocks: run))
            run = []
        }
        for block in blocks {
            if case .mermaid(let source) = block.kind {
                flush()
                segments.append(.mermaid(id: block.id, source: source))
            } else {
                run.append(block)
            }
        }
        flush()
        return segments
    }
}

struct MarkdownMessageView: View {
    var text: String
    var mermaidAsCode: Bool
    /// While the turn is still streaming, Mermaid fences stay as source (the fence may be incomplete).
    var streaming: Bool = false
    @State private var blocks: [RenderedBlock] = []

    var body: some View {
        // First appearance parses synchronously so a bubble never flashes empty; from then on
        // every update (each streaming flush) is parsed off the main thread and reuses
        // already-parsed blocks, so only the trailing block costs anything.
        let shown = blocks.isEmpty ? MarkdownRenderer.render(text, reusing: []) : blocks
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MessageSegment.group(shown)) { segment in
                switch segment {
                case .text(_, let run):
                    SelectableTextView(text: MarkdownTextBuilder.build(run))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .mermaid(_, let value):
                    if mermaidAsCode || streaming {
                        MermaidSourceView(source: value)
                    } else {
                        MermaidBlockView(source: value)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: text) {
            let previous = blocks.isEmpty ? shown : blocks
            let next = await MarkdownRenderer.renderInBackground(text, reusing: previous)
            if !Task.isCancelled, next != blocks { blocks = next }
        }
    }
}

nonisolated enum MarkdownBlock: Hashable, Sendable {
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
