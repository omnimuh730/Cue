import Foundation

/// One item of a bulleted, numbered, or task list. `level` is the nesting depth (0 = top).
/// `marker` is what is drawn in the gutter: the number for ordered lists, a bullet otherwise,
/// a box for task items.
nonisolated struct ListItem: Hashable, Sendable {
    var level: Int
    var marker: String
    var text: String
}

nonisolated enum TableAlignment: Hashable, Sendable {
    case left
    case center
    case right
}

nonisolated enum MarkdownBlock: Hashable, Sendable {
    case paragraph(String)
    case heading(level: Int, String)
    case code(language: String, String)
    case mermaid(String)
    case list(ordered: Bool, items: [ListItem])
    /// Quote paragraphs, `>` stripped, joined with newlines.
    case blockquote(String)
    /// Header row, one alignment per column, then body rows (each padded or cut to the header width).
    case table(header: [String], alignments: [TableAlignment], rows: [[String]])
    case rule
}

/// Splits assistant Markdown into block-level pieces: fenced code and Mermaid, headings, lists,
/// block quotes, pipe tables, rules, and paragraphs. Inline formatting inside any of them is
/// left to `AttributedString(markdown:)`.
///
/// The splitter runs on every streaming flush, so it is a single pass over the lines with a
/// little state rather than a full CommonMark parser. Where CommonMark and what models actually
/// emit disagree, it follows the models: a list or quote may start right under a paragraph line,
/// and a table needs its `|---|` separator before it counts (so a table being streamed stays a
/// paragraph until its header is complete instead of flickering between kinds).
nonisolated enum MarkdownBlocks {
    static let maxListDepth = 3

    static func split(_ text: String) -> [MarkdownBlock] {
        var builder = Builder()
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            builder.consume(line)
        }
        return builder.finish()
    }

    // MARK: - Line classification

    nonisolated struct ListLine: Equatable {
        var level: Int
        var ordered: Bool
        var marker: String
        var text: String
    }

    /// `- item`, `* item`, `+ item`, `1. item`, `1) item`, with optional `[ ]` / `[x]` task box.
    static func listLine(_ line: String) -> ListLine? {
        var index = line.startIndex
        var indent = 0
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            indent += line[index] == "\t" ? 4 : 1
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }
        let level = min(maxListDepth, indent / 2)

        var ordered = false
        var marker: String
        let first = line[index]
        if first == "-" || first == "*" || first == "+" {
            marker = "•"
            index = line.index(after: index)
        } else if first.isNumber {
            var digits = ""
            while index < line.endIndex, line[index].isNumber, digits.count < 9 {
                digits.append(line[index])
                index = line.index(after: index)
            }
            guard index < line.endIndex, line[index] == "." || line[index] == ")" else { return nil }
            ordered = true
            marker = digits + "."
            index = line.index(after: index)
        } else {
            return nil
        }
        // The marker must be followed by a space; "-foo" and "3.14" are prose.
        guard index < line.endIndex, line[index] == " " || line[index] == "\t" else { return nil }
        var text = line[index...].trimmingCharacters(in: .whitespaces)
        if !ordered {
            if text.hasPrefix("[ ] ") || text == "[ ]" {
                marker = "☐"
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if text.lowercased().hasPrefix("[x] ") || text.lowercased() == "[x]" {
                marker = "☑"
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ListLine(level: level, ordered: ordered, marker: marker, text: text)
    }

    /// Three or more of the same `-`, `*`, or `_`, optionally spaced, and nothing else.
    static func isRule(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        var count = 0
        for character in trimmed {
            if character == first {
                count += 1
            } else if character != " " {
                return false
            }
        }
        return count >= 3
    }

    /// Cells of a pipe row (`| a | b |` or `a | b`); nil when the line has no pipe.
    static func tableCells(_ trimmed: String) -> [String]? {
        guard trimmed.contains("|") else { return nil }
        var body = Substring(trimmed)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body = body.dropLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// `|---|:--:|--:|` → one alignment per column; nil when the row is not a separator.
    static func tableSeparator(_ trimmed: String) -> [TableAlignment]? {
        guard let cells = tableCells(trimmed), !cells.isEmpty else { return nil }
        var alignments: [TableAlignment] = []
        for cell in cells {
            let dashes = cell.filter { $0 == "-" }.count
            let rest = cell.filter { $0 != "-" && $0 != ":" && $0 != " " }
            guard dashes >= 1, rest.isEmpty else { return nil }
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            alignments.append(left && right ? .center : right ? .right : .left)
        }
        return alignments
    }

    static func heading(from line: String) -> (level: Int, text: String)? {
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

    // MARK: - Streaming line consumer

    private struct Builder {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: (language: String, lines: [String])?
        var list: (ordered: Bool, items: [ListItem])?
        var quote: [String] = []
        var table: (header: [String], alignments: [TableAlignment], rows: [[String]])?
        /// A pipe row that becomes a table header if the next line is a separator.
        var pendingHeader: (line: String, cells: [String])?

        mutating func consume(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var open = fence {
                if trimmed.hasPrefix("```") {
                    blocks.append(Self.fenceBlock(open))
                    fence = nil
                } else {
                    open.lines.append(line)
                    fence = open
                }
                return
            }

            // A pending header only survives if this line is its separator.
            if let pending = pendingHeader {
                pendingHeader = nil
                if let alignments = MarkdownBlocks.tableSeparator(trimmed) {
                    flushParagraph()
                    let width = pending.cells.count
                    var aligned = Array(alignments.prefix(width))
                    while aligned.count < width { aligned.append(.left) }
                    table = (pending.cells, aligned, [])
                    return
                }
                paragraph.append(pending.line)
            }

            if trimmed.hasPrefix("```") {
                flushAll()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                fence = (language, [])
                return
            }

            if trimmed.isEmpty {
                flushAll()
                return
            }

            if var open = table {
                if let cells = MarkdownBlocks.tableCells(trimmed) {
                    let width = open.header.count
                    var row = Array(cells.prefix(width))
                    while row.count < width { row.append("") }
                    open.rows.append(row)
                    table = open
                    return
                }
                flushTable()
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                var body = trimmed.dropFirst()
                if body.hasPrefix(" ") { body = body.dropFirst() }
                quote.append(String(body))
                return
            }
            flushQuote()

            if MarkdownBlocks.isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                return
            }

            if let heading = MarkdownBlocks.heading(from: trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, heading.text))
                return
            }

            if let item = MarkdownBlocks.listLine(line) {
                if var open = list {
                    open.items.append(ListItem(level: item.level, marker: item.marker, text: item.text))
                    list = open
                    return
                }
                // Like CommonMark, only a "1." list may break into a paragraph; "2024. A year"
                // mid-prose is prose. Bullets always start a list.
                if paragraph.isEmpty || !item.ordered || item.marker == "1." {
                    flushParagraph()
                    list = (item.ordered, [ListItem(level: item.level, marker: item.marker, text: item.text)])
                    return
                }
            }

            if var open = list {
                // A wrapped line continues the last item.
                open.items[open.items.count - 1].text += "\n" + trimmed
                list = open
                return
            }

            if let cells = MarkdownBlocks.tableCells(trimmed), cells.count >= 2 || trimmed.hasPrefix("|") {
                pendingHeader = (line, cells)
                return
            }

            paragraph.append(line)
        }

        mutating func finish() -> [MarkdownBlock] {
            if let open = fence {
                blocks.append(Self.fenceBlock(open))
                fence = nil
            }
            if let pending = pendingHeader {
                paragraph.append(pending.line)
                pendingHeader = nil
            }
            flushAll()
            return blocks
        }

        private mutating func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
            flushTable()
        }

        private mutating func flushParagraph() {
            let joined = paragraph.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraph = []
        }

        private mutating func flushList() {
            if let open = list, !open.items.isEmpty {
                blocks.append(.list(ordered: open.ordered, items: open.items))
            }
            list = nil
        }

        private mutating func flushQuote() {
            let joined = quote.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.blockquote(joined))
            }
            quote = []
        }

        private mutating func flushTable() {
            if let open = table {
                blocks.append(.table(header: open.header, alignments: open.alignments, rows: open.rows))
            }
            table = nil
        }

        private static func fenceBlock(_ fence: (language: String, lines: [String])) -> MarkdownBlock {
            let body = fence.lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if fence.language == "mermaid" { return .mermaid(body) }
            return .code(language: fence.language, body)
        }
    }
}
