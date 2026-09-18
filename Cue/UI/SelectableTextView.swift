import AppKit
import SwiftUI

/// Builds the rich text shown for a run of Markdown blocks: body, headings, fenced code, and
/// inline strong / emphasis / code from the parsed `AttributedString`s. Pure, so it is testable.
///
/// Every block's attributes depend only on its own content and whether it is the first block in
/// the run — never on what follows it. That keeps the attributed string append-only while a turn
/// streams, so `SelectableTextView` can patch just the tail instead of relaying out the message.
nonisolated enum MarkdownTextBuilder {
    static let bodySize: CGFloat = 15.5
    static let bodyLineSpacing: CGFloat = 6
    static let codeSize: CGFloat = 13
    static let blockGap: CGFloat = 12

    static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 22
        case 2: 19
        case 3: 17
        default: bodySize
        }
    }

    /// Text-only blocks (no Mermaid) become one attributed string; blocks are separated by a
    /// paragraph gap so the whole run selects and copies as continuous prose.
    static func build(_ blocks: [RenderedBlock], textColor: NSColor = .labelColor) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let isFirst = index == 0
            switch block.kind {
            case .paragraph(let value):
                output.append(inline(value, baseFont: .systemFont(ofSize: bodySize), color: textColor, paragraph: body(isFirst: isFirst)))
            case .heading(let level, let value):
                let font = NSFont.systemFont(ofSize: headingSize(level), weight: .semibold)
                let style = body(isFirst: isFirst)
                style.paragraphSpacingBefore += isFirst ? 0 : (level <= 2 ? 6 : 2)
                style.lineSpacing = 2
                output.append(inline(value, baseFont: font, color: textColor, paragraph: style))
            case .code(_, let source, _):
                output.append(codeBlock(source, color: textColor, isFirst: isFirst))
            case .mermaid(let source):
                // Callers split runs at Mermaid blocks; if one slips through, show its source.
                output.append(codeBlock(source, color: textColor, isFirst: isFirst))
            case .list(_, let items):
                output.append(list(items, color: textColor, isFirst: isFirst))
            case .blockquote(let paragraphs):
                output.append(blockquote(paragraphs, isFirst: isFirst))
            case .table(let header, let alignments, let rows):
                output.append(table(header: header, alignments: alignments, rows: rows, color: textColor, isFirst: isFirst))
            case .rule:
                output.append(rule(isFirst: isFirst))
            }
            if index != blocks.count - 1 { output.append(NSAttributedString(string: "\n")) }
        }
        return output
    }

    // MARK: Lists

    /// Indent per nesting level and the gap between a marker and its text.
    static let listIndentStep: CGFloat = 20
    static let listMarkerWidth: CGFloat = 22

    /// Each item is one paragraph: marker, tab, text. The hanging indent makes wrapped lines
    /// align under the first word rather than the marker, and the tab stop keeps every marker
    /// column straight whether it is "•", "10.", or "☑".
    private static func list(_ items: [RenderedListItem], color: NSColor, isFirst: Bool) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: bodySize)
        for (index, item) in items.enumerated() {
            let indent = CGFloat(item.level) * listIndentStep
            let style = NSMutableParagraphStyle()
            style.lineSpacing = bodyLineSpacing
            style.lineBreakMode = .byWordWrapping
            style.firstLineHeadIndent = indent
            style.headIndent = indent + listMarkerWidth
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + listMarkerWidth)]
            style.defaultTabInterval = listMarkerWidth
            style.paragraphSpacingBefore = index == 0 ? (isFirst ? 0 : blockGap) : 3
            let markerColor = item.marker == "•" ? NSColor.secondaryLabelColor : color
            output.append(NSAttributedString(string: item.marker + "\t", attributes: [
                .font: font,
                .foregroundColor: markerColor,
                .paragraphStyle: style
            ]))
            output.append(inline(item.text, baseFont: font, color: color, paragraph: style))
            if index != items.count - 1 { output.append(NSAttributedString(string: "\n")) }
        }
        return output
    }

    // MARK: Block quotes

    /// Inset from the column edge to the quote's text; the bar is drawn in that gap.
    static let quoteInset: CGFloat = 16

    /// Secondary text, indented, tagged with `quoteAttribute` so `SelectableNSTextView` draws a
    /// bar down its left. Paragraphs are joined with line separators rather than newlines: the
    /// tag then runs unbroken over the whole quote and the bar spans it as one piece.
    private static func blockquote(_ paragraphs: [AttributedString], isFirst: Bool) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = bodyLineSpacing
        style.lineBreakMode = .byWordWrapping
        style.firstLineHeadIndent = quoteInset
        style.headIndent = quoteInset
        style.paragraphSpacingBefore = isFirst ? 0 : blockGap
        let font = NSFont.systemFont(ofSize: bodySize)
        let output = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            output.append(inline(paragraph, baseFont: font, color: .secondaryLabelColor, paragraph: style))
            if index != paragraphs.count - 1 {
                output.append(NSAttributedString(string: "\u{2028}\u{2028}", attributes: [
                    .font: font,
                    .paragraphStyle: style
                ]))
            }
        }
        output.addAttribute(quoteAttribute, value: true, range: NSRange(location: 0, length: output.length))
        return output
    }

    // MARK: Tables

    /// An `NSTextTable` with one `NSTextTableBlock` per cell. Cells wrap to the column width
    /// instead of scrolling — right for a window that is often narrow — and the whole table
    /// selects and copies as text, row by row.
    private static func table(
        header: [AttributedString],
        alignments: [TableAlignment],
        rows: [[AttributedString]],
        color: NSColor,
        isFirst: Bool
    ) -> NSAttributedString {
        let columns = max(1, header.count)
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.setWidth(isFirst ? 0 : blockGap, type: .absoluteValueType, for: .margin, edge: .minY)

        let output = NSMutableAttributedString()
        let hairline = NSColor.labelColor.withAlphaComponent(0.14)
        let allRows = [header] + rows
        for (rowIndex, row) in allRows.enumerated() {
            let isHeader = rowIndex == 0
            for column in 0..<columns {
                let cell = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(1, type: .absoluteValueType, for: .border)
                cell.setBorderColor(hairline)
                cell.setWidth(6, type: .absoluteValueType, for: .padding, edge: .minY)
                cell.setWidth(6, type: .absoluteValueType, for: .padding, edge: .maxY)
                cell.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxX)
                if isHeader { cell.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05) }

                let style = NSMutableParagraphStyle()
                style.textBlocks = [cell]
                style.lineSpacing = 2
                style.lineBreakMode = .byWordWrapping
                switch column < alignments.count ? alignments[column] : .left {
                case .left: style.alignment = .left
                case .center: style.alignment = .center
                case .right: style.alignment = .right
                }
                let font = isHeader
                    ? NSFont.systemFont(ofSize: bodySize - 1, weight: .semibold)
                    : NSFont.systemFont(ofSize: bodySize - 1)
                let content = column < row.count ? row[column] : AttributedString()
                let text = inline(content, baseFont: font, color: color, paragraph: style)
                if text.length == 0 {
                    // An empty cell still needs a paragraph to draw its borders.
                    output.append(NSAttributedString(string: "\u{200B}", attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: style
                    ]))
                } else {
                    output.append(text)
                }
                let isLastCell = rowIndex == allRows.count - 1 && column == columns - 1
                if !isLastCell { output.append(NSAttributedString(string: "\n")) }
            }
        }
        return output
    }

    // MARK: Rules

    /// One short, blank paragraph tagged with `ruleAttribute`; the text view draws the hairline
    /// across it. The no-break space gives the paragraph a glyph, so it gets a line fragment.
    private static func rule(isFirst: Bool) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = isFirst ? 0 : blockGap
        style.minimumLineHeight = 9
        style.maximumLineHeight = 9
        return NSAttributedString(string: "\u{00A0}", attributes: [
            .font: NSFont.systemFont(ofSize: 6),
            .foregroundColor: NSColor.clear,
            .paragraphStyle: style,
            ruleAttribute: true
        ])
    }

    /// Custom attributes for decorations TextKit does not draw for us (on this OS a plain
    /// `NSTextBlock` lays out its padding but never paints borders or backgrounds).
    static let quoteAttribute = NSAttributedString.Key("cue.quote")
    static let ruleAttribute = NSAttributedString.Key("cue.rule")

    static func plain(_ text: String, size: CGFloat = 15, color: NSColor = .labelColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
    }

    /// Monospaced text for a fenced block. `CodeBlockView` draws its own frame and line numbers,
    /// so this carries no background or block margins. Long lines wrap to the column.
    static func code(_ source: String, spans: [HighlightSpan] = [], color: NSColor = .labelColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.lineBreakMode = .byWordWrapping
        let output = NSMutableAttributedString(string: source, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
        let length = output.length
        for span in spans where span.range.upperBound <= length {
            output.addAttribute(
                .foregroundColor,
                value: CodeTheme.color(for: span.token),
                range: NSRange(location: span.range.lowerBound, length: span.range.count)
            )
        }
        return output
    }

    private static func body(isFirst: Bool) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = bodyLineSpacing
        style.paragraphSpacingBefore = isFirst ? 0 : blockGap
        style.lineBreakMode = .byWordWrapping
        return style
    }

    /// Maps Foundation's inline presentation intents (from `AttributedString(markdown:)`) onto fonts.
    static func inline(_ value: AttributedString, baseFont: NSFont, color: NSColor, paragraph: NSParagraphStyle) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for run in value.runs {
            let text = String(value[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var font = baseFont
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: baseFont.pointSize - 1.5, weight: .regular)
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if !traits.isEmpty {
                let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
                font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            if intent.contains(.code) {
                attributes[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.07)
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
            }
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }

    private static func codeBlock(_ source: String, color: NSColor, isFirst: Bool) -> NSAttributedString {
        let block = NSTextBlock()
        block.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06)
        block.setWidth(12, type: .absoluteValueType, for: .padding)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(0, type: .absoluteValueType, for: .margin, edge: .maxY)
        block.setWidth(isFirst ? 0 : blockGap, type: .absoluteValueType, for: .margin, edge: .minY)
        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.lineSpacing = 3
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: source, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
    }
}

/// Six semantic colors for code, all system dynamic colors so they hold up in light and dark
/// and under Reduce Transparency. Deliberately few: the column should stay calm, not festive.
nonisolated enum CodeTheme {
    static func color(for token: HighlightToken) -> NSColor {
        switch token {
        case .keyword: .systemPurple
        case .string: .systemRed
        case .comment: .secondaryLabelColor
        case .number: .systemBlue
        case .type: .systemTeal
        case .attribute: .systemOrange
        case .tag: .systemIndigo
        }
    }
}

/// Character-level reveal used while a turn streams: everything past `reveal` is withheld and the
/// last few characters ramp from transparent to solid, so text arrives as a soft wipe rather than
/// in 40 ms steps. Pure, so the ramp is unit-testable.
nonisolated enum StreamingTextReveal {
    /// How many characters the fade spans. ~0.3 s of tail at a typical token rate.
    static let fadeSpan = 16

    /// Alpha for a character `distance` positions back from the reveal head.
    static func alpha(distance: Int, span: Int = fadeSpan) -> CGFloat {
        guard span > 0 else { return 1 }
        guard distance >= 0 else { return 0 }
        guard distance < span else { return 1 }
        // Ease-out so characters firm up quickly and only the newest few are faint.
        let progress = CGFloat(distance + 1) / CGFloat(span)
        return progress * progress
    }

    /// The visible prefix of `text`, with the fade ramp applied to its tail.
    /// Returns `text` untouched when nothing is withheld.
    static func apply(_ text: NSAttributedString, reveal: Int?) -> NSAttributedString {
        guard let reveal, reveal < text.length else { return text }
        guard reveal > 0 else { return NSAttributedString() }
        // Cutting inside an emoji or a combining sequence would render a broken glyph.
        let cut = (text.string as NSString).rangeOfComposedCharacterSequence(at: reveal).location
        guard cut > 0 else { return NSAttributedString() }
        let shown = NSMutableAttributedString(
            attributedString: text.attributedSubstring(from: NSRange(location: 0, length: cut))
        )
        let string = shown.string as NSString
        shown.beginEditing()
        var index = cut
        var distance = 0
        while index > 0, distance < fadeSpan {
            let character = string.rangeOfComposedCharacterSequence(at: index - 1)
            let base = shown.attribute(.foregroundColor, at: character.location, effectiveRange: nil) as? NSColor ?? .labelColor
            shown.addAttribute(
                .foregroundColor,
                value: base.withAlphaComponent(base.alphaComponent * alpha(distance: distance)),
                range: character
            )
            index = character.location
            distance += 1
        }
        shown.endEditing()
        return shown
    }
}

/// Works out how little of an already laid-out attributed string has to be rewritten to turn it
/// into a new one. Pure, so the boundary it picks is unit-testable.
nonisolated enum IncrementalText {
    /// Characters rewound past the common prefix before patching, as insurance against a
    /// formatting change that kept its characters.
    static let guardBand = 8

    /// Length of the leading run both strings share and that can safely be left laid out.
    ///
    /// Inline Markdown can restyle text it already emitted — `*word` stays literal until the
    /// closing `*` arrives — but the markers themselves are dropped from the output, so the two
    /// strings always diverge at or before the restyled range. Block attributes never depend on
    /// what follows them (see `MarkdownTextBuilder`), so the shared prefix, less a small guard
    /// band, is stable.
    ///
    /// `volatileTail` is how many trailing characters carry the streaming fade ramp — in the text
    /// already on screen as well as in the replacement. Those characters share their neighbours'
    /// glyphs but not their alpha, so leaving any of them in place strands a grey band in the
    /// finished message.
    static func stablePrefix(of current: NSAttributedString, and next: NSAttributedString, volatileTail: Int) -> Int {
        let ceiling = min(current.length, next.length) - max(0, volatileTail)
        guard ceiling > 0 else { return 0 }
        let old = current.string as NSString
        let shared = old.commonPrefix(with: next.string).utf16.count
        let start = max(0, min(shared, ceiling) - guardBand)
        guard start > 0, start < old.length else { return start }
        // Never split an emoji or a combining sequence; both strings share this prefix, so the
        // boundary found here is valid in either.
        return old.rangeOfComposedCharacterSequence(at: start).location
    }
}

/// Read-only, freely selectable rich text that sizes itself to its content. Replaces SwiftUI
/// `Text` for chat messages so a drag can select across paragraphs and code, ⌘C and the context
/// menu work, and a click inside Cue's non-activating panel takes key status for copying.
struct SelectableTextView: NSViewRepresentable {
    var text: NSAttributedString
    /// Characters to show, or `nil` for all of them. Drives the streaming reveal.
    var reveal: Int?
    /// Prose wraps to the reading column; a code block keeps its lines and scrolls sideways.
    var wraps: Bool

    init(text: NSAttributedString, reveal: Int? = nil, wraps: Bool = true) {
        self.text = text
        self.reveal = reveal
        self.wraps = wraps
    }

    /// The visible text, fade ramp included. Recomputed per update; the view then patches only
    /// the part that actually moved.
    private var shown: NSAttributedString {
        StreamingTextReveal.apply(text, reveal: reveal)
    }

    func makeNSView(context: Context) -> SelectableNSTextView {
        let view = SelectableNSTextView.make(wraps: wraps)
        let value = shown
        view.textStorage?.setAttributedString(value)
        view.noteFadedTail(value.length < text.length ? StreamingTextReveal.fadeSpan : 0)
        return view
    }

    func updateNSView(_ view: SelectableNSTextView, context: Context) {
        let value = shown
        // A withheld tail means the ramp is in play; once nothing is withheld the text is solid.
        let faded = value.length < text.length ? StreamingTextReveal.fadeSpan : 0
        if view.apply(value, fadedTail: faded) {
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectableNSTextView, context: Context) -> CGSize? {
        guard wraps else { return nsView.naturalSize() }
        // A zero-width probe is SwiftUI asking for the minimum; the text has no opinion, so it
        // answers with the last height instead of laying out a one-glyph column.
        let width = proposal.width ?? nsView.bounds.width
        // A zero or infinite width is a probe, not a column; measuring at it would lay the text
        // out as one glyph per line or one line per paragraph and report that height.
        guard width > 1, width.isFinite else { return CGSize(width: width, height: nsView.lastMeasuredHeight) }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }
}

final class SelectableNSTextView: NSTextView {
    /// False for text that keeps its line breaks and scrolls horizontally instead.
    var wrapsText = true
    private var lastWidth: CGFloat = -1
    private var lastHeight: CGFloat = 0
    /// Heights already measured for this text, by width. A live resize asks for the same width
    /// several times per layout pass and for the previous width again on the next; laying out a
    /// long message once per distinct width instead of once per ask is what keeps the drag smooth.
    private var heightsByWidth: [CGFloat: CGFloat] = [:]

    var lastMeasuredHeight: CGFloat { lastHeight }

    /// A read-only, selectable text view with its own TextKit stack and no insets, so line
    /// fragments sit exactly where the view's coordinates say they do.
    static func make(wraps: Bool) -> SelectableNSTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(
                width: wraps ? 0 : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        container.widthTracksTextView = wraps
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let view = SelectableNSTextView(frame: .zero, textContainer: container)
        view.drawsBackground = false
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.usesFontPanel = false
        view.isAutomaticLinkDetectionEnabled = false
        view.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        view.textContainerInset = .zero
        // SwiftUI owns the frame. TextKit must never grow the view to fit a paragraph on its own:
        // a self-sized view paints past the slot SwiftUI measured for it and over the next bubble.
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = !wraps
        view.autoresizingMask = []
        // Layer-backed views do not clip by default. Between the frame AppKit applies and the
        // height SwiftUI measured there can be one resize tick of disagreement; clipping keeps
        // that tick to a cropped last line rather than text drawn across its neighbours.
        view.clipsToBounds = true
        view.wrapsText = wraps
        view.focusRingType = .none
        view.setAccessibilityRole(.staticText)
        return view
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: lastHeight)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDecorations()
    }

    /// Quote bars and rules. Both live beside or between glyphs, never under them, so drawing
    /// after the text is fine.
    private func drawDecorations() {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(MarkdownTextBuilder.quoteAttribute, in: full) { value, range, _ in
            guard value as? Bool == true else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            guard !bounds.isEmpty else { return }
            let bar = NSRect(x: origin.x, y: bounds.minY + origin.y, width: 3, height: bounds.height)
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
        storage.enumerateAttribute(MarkdownTextBuilder.ruleAttribute, in: full) { value, range, _ in
            guard value as? Bool == true else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let y = (line.midY + origin.y).rounded() - 0.5
            let rule = NSRect(x: origin.x, y: y, width: textContainer.size.width, height: 1)
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            rule.fill()
        }
    }

    /// Characters at the end of the storage that carry the streaming fade ramp. They have to be
    /// rewritten even when their glyphs did not change, or the ramp freezes into the message.
    private var fadedTail = 0

    /// Replaces only the part of the storage that actually changed.
    ///
    /// While a turn streams, `next` shares a long prefix with what is already laid out, so the
    /// edit is a short append near the end and TextKit relays out one paragraph instead of the
    /// whole message. Returns whether anything changed.
    @discardableResult
    func apply(_ next: NSAttributedString, fadedTail nextFaded: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let stable = IncrementalText.stablePrefix(
            of: storage,
            and: next,
            volatileTail: max(fadedTail, nextFaded)
        )
        fadedTail = nextFaded
        let oldTail = NSRange(location: stable, length: storage.length - stable)
        let newTail = NSRange(location: stable, length: next.length - stable)
        if oldTail.length == 0, newTail.length == 0 { return false }
        let replacement = next.attributedSubstring(from: newTail)
        if oldTail.length == replacement.length,
           storage.attributedSubstring(from: oldTail).isEqual(to: replacement) {
            return false
        }
        let selection = selectedRange()
        storage.beginEditing()
        storage.replaceCharacters(in: oldTail, with: replacement)
        storage.endEditing()
        heightsByWidth.removeAll(keepingCapacity: true)
        // A selection that ends inside the rewritten tail is gone either way; one entirely
        // before it survives the edit untouched.
        if selection.length > 0, selection.location + selection.length <= stable {
            setSelectedRange(selection)
        }
        return true
    }

    /// Records the ramp `makeNSView` seeded the storage with, so the first patch rewrites it.
    func noteFadedTail(_ length: Int) {
        fadedTail = length
    }

    /// Size of the text laid out without wrapping, for a block that scrolls sideways.
    func naturalSize() -> NSSize {
        guard let layoutManager, let textContainer else { return NSSize(width: 0, height: lastHeight) }
        let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if textContainer.containerSize != unbounded { textContainer.containerSize = unbounded }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        lastWidth = ceil(used.width)
        lastHeight = ceil(used.height)
        return NSSize(width: lastWidth, height: lastHeight)
    }

    /// Height of the text wrapped to `width`. Widths are matched on the pixel grid so the
    /// fractional widths a layout pass hands out do not each count as new.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 1, width.isFinite, let layoutManager, let textContainer else { return lastHeight }
        let key = (width * 2).rounded() / 2
        if let cached = heightsByWidth[key] {
            lastWidth = key
            lastHeight = cached
            return cached
        }
        if abs(textContainer.containerSize.width - key) > 0.5 {
            textContainer.containerSize = NSSize(width: key, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        lastWidth = key
        lastHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        heightsByWidth[key] = lastHeight
        return lastHeight
    }

    /// The frame AppKit applies can trail the width SwiftUI last measured by a tick of a live
    /// resize. Wrap to the frame that is actually on screen and ask SwiftUI to measure again so
    /// the slot catches up on its next pass.
    override func layout() {
        super.layout()
        guard wrapsText, let textContainer else { return }
        let width = bounds.width
        guard width > 1 else { return }
        if abs(textContainer.containerSize.width - width) > 0.5 {
            textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        if abs(width - lastWidth) > 0.5 {
            let before = lastHeight
            if abs(height(forWidth: width) - before) > 0.5 { invalidateIntrinsicContentSize() }
        }
    }

    /// A click takes key status without activating the app, so ⌘C reaches this view.
    override func mouseDown(with event: NSEvent) {
        if let window, !window.isKeyWindow { window.makeKey() }
        super.mouseDown(with: event)
    }

    /// The Edit menu only sees key equivalents when Cue is the active app, which it usually is
    /// not; ⌘C and ⌘A are dispatched here instead (see `EditingShortcut`).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = EditingShortcut.action(for: event), NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
