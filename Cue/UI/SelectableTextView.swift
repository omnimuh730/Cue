import AppKit
import SwiftUI

/// Builds the rich text shown for a run of Markdown blocks: body, headings, fenced code, and
/// inline strong / emphasis / code from the parsed `AttributedString`s. Pure, so it is testable.
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
            let isLast = index == blocks.count - 1
            switch block.kind {
            case .paragraph(let value):
                output.append(inline(value, baseFont: .systemFont(ofSize: bodySize), color: textColor, paragraph: body(lastInRun: isLast)))
            case .heading(let level, let value):
                let font = NSFont.systemFont(ofSize: headingSize(level), weight: .semibold)
                let style = body(lastInRun: isLast)
                style.paragraphSpacingBefore = level <= 2 ? 6 : 2
                style.lineSpacing = 2
                output.append(inline(value, baseFont: font, color: textColor, paragraph: style))
            case .code(let source):
                output.append(codeBlock(source, color: textColor, lastInRun: isLast))
            case .mermaid(let source):
                // Callers split runs at Mermaid blocks; if one slips through, show its source.
                output.append(codeBlock(source, color: textColor, lastInRun: isLast))
            }
            if !isLast { output.append(NSAttributedString(string: "\n")) }
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

    private static func body(lastInRun: Bool) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = bodyLineSpacing
        style.paragraphSpacing = lastInRun ? 0 : blockGap
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

    private static func codeBlock(_ source: String, color: NSColor, lastInRun: Bool) -> NSAttributedString {
        let block = NSTextBlock()
        block.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06)
        block.setWidth(12, type: .absoluteValueType, for: .padding)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(lastInRun ? 0 : blockGap, type: .absoluteValueType, for: .margin, edge: .maxY)
        block.setWidth(0, type: .absoluteValueType, for: .margin, edge: .minY)
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

/// Read-only, freely selectable rich text that sizes itself to its content. Replaces SwiftUI
/// `Text` for chat messages so a drag can select across paragraphs and code, ⌘C and the context
/// menu work, and a click inside Cue's non-activating panel takes key status for copying.
struct SelectableTextView: NSViewRepresentable {
    var text: NSAttributedString

    func makeNSView(context: Context) -> SelectableNSTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
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
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.focusRingType = .none
        view.setAccessibilityRole(.staticText)
        view.textStorage?.setAttributedString(text)
        return view
    }

    func updateNSView(_ view: SelectableNSTextView, context: Context) {
        guard let storage = view.textStorage, !storage.isEqual(to: text) else { return }
        let selection = view.selectedRange()
        storage.setAttributedString(text)
        if selection.location + selection.length <= storage.length {
            view.setSelectedRange(selection)
        }
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectableNSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }
}

final class SelectableNSTextView: NSTextView {
    private var lastWidth: CGFloat = -1
    private var lastHeight: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: lastHeight)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
