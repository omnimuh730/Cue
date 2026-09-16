import AppKit
import SwiftUI

nonisolated struct RenderedListItem: Equatable, Sendable {
    var level: Int
    var marker: String
    var text: AttributedString
}

/// A block with its inline Markdown already parsed, ready to draw without further work.
nonisolated struct RenderedBlock: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case paragraph(AttributedString)
        case heading(level: Int, AttributedString)
        /// Fenced code with its syntax spans, tokenized once here so the view only colors.
        case code(language: String, String, spans: [HighlightSpan])
        case mermaid(String)
        case list(ordered: Bool, items: [RenderedListItem])
        /// One entry per quote paragraph.
        case blockquote([AttributedString])
        case table(header: [AttributedString], alignments: [TableAlignment], rows: [[AttributedString]])
        case rule
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
        case .code(let language, let value):
            .code(language: language, value, spans: CodeHighlighter.spans(value, language: language))
        case .mermaid(let value): .mermaid(value)
        case .list(let ordered, let items):
            // Wrapped lines stay inside the item's paragraph so the hanging indent holds.
            .list(ordered: ordered, items: items.map {
                RenderedListItem(level: $0.level, marker: $0.marker, text: parse(softWrapped($0.text)))
            })
        case .blockquote(let value):
            .blockquote(value.components(separatedBy: "\n\n").map { parse(softWrapped($0)) })
        case .table(let header, let alignments, let rows):
            .table(header: header.map { parse($0) }, alignments: alignments, rows: rows.map { $0.map { parse($0) } })
        case .rule: .rule
        }
    }

    /// Newlines become line separators: a break within the paragraph rather than a new one.
    private static func softWrapped(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "\u{2028}")
    }

    private static func parse(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}

/// Consecutive prose blocks render as one selectable text view; code and Mermaid blocks break the
/// run so each can carry its own frame and copy button.
nonisolated enum MessageSegment: Identifiable, Equatable {
    case text(id: Int, blocks: [RenderedBlock])
    case code(id: Int, language: String, source: String, spans: [HighlightSpan])
    case mermaid(id: Int, source: String)

    var id: Int {
        switch self {
        case .text(let id, _), .code(let id, _, _, _), .mermaid(let id, _): id
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
            switch block.kind {
            case .mermaid(let source):
                flush()
                segments.append(.mermaid(id: block.id, source: source))
            case .code(let language, let source, let spans):
                flush()
                segments.append(.code(id: block.id, language: language, source: source, spans: spans))
            case .paragraph, .heading, .list, .blockquote, .table, .rule:
                run.append(block)
            }
        }
        flush()
        return segments
    }
}

/// One drawable piece of a message with its position in the message's character stream, so the
/// streaming reveal can be spread across pieces.
struct MessagePiece: Identifiable {
    enum Body {
        case text(NSAttributedString)
        case code(language: String, source: String, spans: [HighlightSpan])
        case mermaid(String)
    }

    var id: Int
    var offset: Int
    var length: Int
    var body: Body
}

/// A message's Markdown, parsed and laid out into pieces once.
struct MarkdownDocument {
    var text = ""
    var mermaidAsCode = false
    var blocks: [RenderedBlock] = []
    var pieces: [MessagePiece] = []
    var length = 0

    static func make(text: String, mermaidAsCode: Bool, blocks: [RenderedBlock]) -> MarkdownDocument {
        var pieces: [MessagePiece] = []
        var offset = 0
        for segment in MessageSegment.group(blocks) {
            switch segment {
            case .text(let id, let run):
                let value = MarkdownTextBuilder.build(run)
                pieces.append(MessagePiece(id: id, offset: offset, length: value.length, body: .text(value)))
                offset += value.length
            case .code(let id, let language, let source, let spans):
                pieces.append(
                    MessagePiece(
                        id: id,
                        offset: offset,
                        length: source.utf16.count,
                        body: .code(language: language, source: source, spans: spans)
                    )
                )
                offset += source.utf16.count
            case .mermaid(let id, let source):
                pieces.append(MessagePiece(id: id, offset: offset, length: source.utf16.count, body: .mermaid(source)))
                offset += source.utf16.count
            }
        }
        return MarkdownDocument(text: text, mermaidAsCode: mermaidAsCode, blocks: blocks, pieces: pieces, length: offset)
    }
}

/// Keeps parsed messages around after their views are recycled.
///
/// A `LazyVStack` tears down and rebuilds bubbles as the transcript scrolls; without this, every
/// bubble that scrolls back into view re-parses its Markdown and rebuilds its attributed text on
/// the main thread, which is what makes a long transcript stutter and flash empty.
@MainActor
final class MarkdownDocumentStore {
    static let shared = MarkdownDocumentStore()

    /// Roughly a screen or two of history in either direction.
    private let limit = 48
    private var documents: [UUID: MarkdownDocument] = [:]
    private var reveals: [UUID: Double] = [:]
    private var order: [UUID] = []

    func document(for id: UUID, text: String, mermaidAsCode: Bool) -> MarkdownDocument? {
        guard let cached = documents[id], cached.text == text, cached.mermaidAsCode == mermaidAsCode else { return nil }
        touch(id)
        return cached
    }

    func store(_ document: MarkdownDocument, for id: UUID) {
        documents[id] = document
        touch(id)
    }

    func reveal(for id: UUID) -> Double? { reveals[id] }

    func store(reveal: Double, for id: UUID) {
        reveals[id] = reveal
    }

    func forget(_ id: UUID) {
        documents[id] = nil
        reveals[id] = nil
        order.removeAll { $0 == id }
    }

    private func touch(_ id: UUID) {
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            documents[oldest] = nil
            reveals[oldest] = nil
        }
    }
}

/// Paces the streaming reveal: the head chases the text that has arrived, fast enough never to
/// fall behind and slow enough that characters land one at a time instead of in 40 ms slabs.
nonisolated enum RevealPacing {
    static let frameInterval: Duration = .milliseconds(16)
    /// Fraction of the backlog consumed per frame. Settles ~0.15 s behind a live stream.
    static let catchUp: Double = 0.14
    /// Floor so a trickle still moves, in characters per frame.
    static let minimumStep: Double = 0.7
    /// Past this backlog the reveal stops animating and jumps; the reader is too far behind to care.
    static let jumpThreshold: Double = 1_400

    static func advance(_ shown: Double, toward target: Double) -> Double {
        let remaining = target - shown
        guard remaining > 0 else { return target }
        if remaining > jumpThreshold { return target }
        return min(target, shown + max(minimumStep, remaining * catchUp))
    }
}

struct MarkdownMessageView: View {
    /// Identifies the message so its parsed text survives `LazyVStack` recycling.
    var messageID: UUID
    var text: String
    var mermaidAsCode: Bool
    /// While the turn is still streaming, Mermaid fences stay as source (the fence may be incomplete).
    var streaming: Bool = false

    @State private var document = MarkdownDocument()
    /// Characters revealed so far; `.infinity` means "all of it", the state for finished messages.
    @State private var revealed: Double
    @State private var revealing: Bool

    init(messageID: UUID, text: String, mermaidAsCode: Bool, streaming: Bool = false) {
        self.messageID = messageID
        self.text = text
        self.mermaidAsCode = mermaidAsCode
        self.streaming = streaming
        // Resolved here rather than in `onAppear` so a bubble never paints its full text for one
        // frame before the wipe starts. A recycled view picks up where its reveal left off.
        let resumed = MarkdownDocumentStore.shared.reveal(for: messageID)
        let start = resumed ?? (streaming ? 0 : .infinity)
        _revealed = State(initialValue: start)
        _revealing = State(initialValue: streaming || start.isFinite)
    }

    var body: some View {
        let shown = visibleDocument
        VStack(alignment: .leading, spacing: 12) {
            ForEach(shown.pieces) { piece in
                switch piece.body {
                case .text(let value):
                    SelectableTextView(text: value, reveal: reveal(for: piece))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let source, let spans):
                    // A block below the reveal head has not "arrived" yet; showing it early would
                    // run ahead of the prose wiping in above it.
                    if hasReached(piece) {
                        CodeBlockView(language: language, source: source, spans: spans)
                    }
                case .mermaid(let source):
                    if hasReached(piece) {
                        if mermaidAsCode || streaming {
                            CodeBlockView(language: "mermaid", source: source)
                        } else {
                            MermaidBlockView(source: source)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: text) { await reparse() }
        .task(id: [revealing, streaming]) { await runReveal() }
        .onChange(of: streaming) { _, isStreaming in
            if isStreaming { revealing = true }
        }
        .onDisappear { MarkdownDocumentStore.shared.store(reveal: revealed, for: messageID) }
    }

    /// The parsed text to draw right now.
    ///
    /// Parsing the current text inline happens only when there is nothing at all to show, so a
    /// bubble never flashes empty. Once anything is parsed, a flush that has not been reparsed
    /// yet keeps drawing the previous pass: the background reparse lands within a frame or two,
    /// and the reveal head trails further behind than that in any case.
    private var visibleDocument: MarkdownDocument {
        if document.matches(text: text, mermaidAsCode: mermaidAsCode) { return document }
        let store = MarkdownDocumentStore.shared
        if let cached = store.document(for: messageID, text: text, mermaidAsCode: mermaidAsCode) { return cached }
        if !document.pieces.isEmpty { return document }
        let made = MarkdownDocument.make(
            text: text,
            mermaidAsCode: mermaidAsCode,
            blocks: MarkdownRenderer.render(text, reusing: [])
        )
        store.store(made, for: messageID)
        return made
    }

    /// Whether the reveal has reached a piece that is drawn whole rather than character by
    /// character.
    private func hasReached(_ piece: MessagePiece) -> Bool {
        revealed >= Double(piece.offset)
    }

    /// Characters of this piece to show, or `nil` once the reveal has passed it entirely.
    private func reveal(for piece: MessagePiece) -> Int? {
        guard revealed.isFinite else { return nil }
        let local = revealed - Double(piece.offset)
        if local >= Double(piece.length) { return nil }
        return max(0, Int(local))
    }

    private func reparse() async {
        if let cached = MarkdownDocumentStore.shared.document(for: messageID, text: text, mermaidAsCode: mermaidAsCode) {
            document = cached
            return
        }
        let blocks = await MarkdownRenderer.renderInBackground(text, reusing: document.blocks)
        guard !Task.isCancelled else { return }
        let next = MarkdownDocument.make(text: text, mermaidAsCode: mermaidAsCode, blocks: blocks)
        MarkdownDocumentStore.shared.store(next, for: messageID)
        document = next
        if revealed.isFinite, revealed < Double(next.length) { revealing = true }
    }

    /// Runs only while there is something left to wipe in, so a quiet transcript costs no frames.
    private func runReveal() async {
        guard revealing else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: RevealPacing.frameInterval)
            if Task.isCancelled { return }
            let target = Double(document.length)
            let next = RevealPacing.advance(min(revealed, target), toward: target)
            revealed = next
            MarkdownDocumentStore.shared.store(reveal: next, for: messageID)
            if !streaming, next >= target {
                revealed = .infinity
                MarkdownDocumentStore.shared.store(reveal: .infinity, for: messageID)
                revealing = false
                return
            }
        }
    }
}

private extension MarkdownDocument {
    func matches(text other: String, mermaidAsCode flag: Bool) -> Bool {
        !pieces.isEmpty && text == other && mermaidAsCode == flag
    }
}
