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
            case .code(_, let source):
                output.append(codeBlock(source, color: textColor, isFirst: isFirst))
            case .mermaid(let source):
                // Callers split runs at Mermaid blocks; if one slips through, show its source.
                output.append(codeBlock(source, color: textColor, isFirst: isFirst))
            }
            if index != blocks.count - 1 { output.append(NSAttributedString(string: "\n")) }
        }
        return output
    }

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

    /// Monospaced text for a fenced block. `CodeBlockView` draws its own frame, so this carries
    /// no background or block margins.
    static func code(_ source: String, color: NSColor = .labelColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.lineBreakMode = .byClipping
        return NSAttributedString(string: source, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
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
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = !wraps
        view.autoresizingMask = wraps ? [.width] : []
        view.wrapsText = wraps
        view.focusRingType = .none
        view.setAccessibilityRole(.staticText)
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
        let width = proposal.width ?? nsView.bounds.width
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }
}

final class SelectableNSTextView: NSTextView {
    /// False for code blocks, which keep their line breaks and scroll horizontally instead.
    var wrapsText = true
    private var lastWidth: CGFloat = -1
    private var lastHeight: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: lastHeight)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 1, let layoutManager, let textContainer else { return lastHeight }
        if abs(textContainer.containerSize.width - width) > 0.5 {
            textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        lastWidth = width
        lastHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        return lastHeight
    }

    override func layout() {
        super.layout()
        guard wrapsText else { return }
        if abs(bounds.width - lastWidth) > 0.5 {
            let before = lastHeight
            if abs(height(forWidth: bounds.width) - before) > 0.5 { invalidateIntrinsicContentSize() }
        }
    }

    /// A click takes key status without activating the app, so ⌘C reaches this view.
    override func mouseDown(with event: NSEvent) {
        if let window, !window.isKeyWindow { window.makeKey() }
        super.mouseDown(with: event)
    }
}
