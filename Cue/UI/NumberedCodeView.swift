import AppKit
import SwiftUI

/// Wrapping code with a thin line-number gutter.
///
/// The gutter numbers source lines, not laid-out rows: a line that wraps to the column gets one
/// number and its continuation rows stay blank, so the numbers still match the file the code came
/// from. Numbers are drawn beside the text view rather than as part of it, so a drag-select or
/// ⌘A copies only the code.
struct NumberedCodeView: NSViewRepresentable {
    /// Selecting a snippet offers the same actions as selecting prose.
    @Environment(\.selectMessageText) private var selectMessageText
    var text: NSAttributedString

    func makeNSView(context: Context) -> NumberedCodeNSView {
        let view = NumberedCodeNSView()
        view.onSelect = selectMessageText
        view.apply(text)
        return view
    }

    func updateNSView(_ view: NumberedCodeNSView, context: Context) {
        view.onSelect = selectMessageText
        view.apply(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NumberedCodeNSView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }
}

/// Line-number layout, kept pure so it is unit-testable.
nonisolated enum CodeLineNumbers {
    /// Character offsets where each source line starts (UTF-16, as TextKit counts). A trailing
    /// newline yields a final empty line, as an editor would show.
    static func lineStarts(in text: String) -> [Int] {
        var starts = [0]
        let utf16 = text.utf16
        var offset = 0
        for unit in utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        return starts
    }

    /// Room for the widest number plus breathing space either side of the hairline.
    static func gutterWidth(lineCount: Int, digitWidth: CGFloat) -> CGFloat {
        let digits = max(2, String(max(lineCount, 1)).count)
        return ceil(CGFloat(digits) * digitWidth) + leadingInset + trailingInset
    }

    static let leadingInset: CGFloat = 12
    static let trailingInset: CGFloat = 10
    /// Gap between the hairline and the first column of code.
    static let codeInset: CGFloat = 10
}

final class NumberedCodeNSView: NSView {
    private let textView = SelectableNSTextView.make(wraps: true)
    private let gutter = LineNumberGutter()
    private var lastHeight: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        gutter.textView = textView
        addSubview(gutter)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: lastHeight)
    }

    /// Passed through to the code's text view, which reports selections like any other message text.
    var onSelect: ((String, CGRect) -> Void)? {
        get { textView.onSelect }
        set { textView.onSelect = newValue }
    }

    func apply(_ text: NSAttributedString) {
        let lineCount = CodeLineNumbers.lineStarts(in: text.string).count
        let changed = textView.apply(text, fadedTail: 0)
        let widthChanged = gutter.setLineCount(lineCount)
        if changed || widthChanged {
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
        gutter.needsDisplay = true
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let column = max(1, width - gutter.width - CodeLineNumbers.codeInset)
        lastHeight = textView.height(forWidth: column)
        return lastHeight
    }

    override func layout() {
        super.layout()
        let gutterWidth = gutter.width
        let codeX = gutterWidth + CodeLineNumbers.codeInset
        gutter.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        textView.frame = NSRect(x: codeX, y: 0, width: max(1, bounds.width - codeX), height: bounds.height)
        gutter.needsDisplay = true
    }
}

/// Draws one number per source line, aligned to the baseline of that line's first row.
final class LineNumberGutter: NSView {
    weak var textView: SelectableNSTextView?
    private(set) var width: CGFloat = 0
    private var lineCount = 0

    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .light)
    private lazy var digitWidth: CGFloat = ("0" as NSString).size(withAttributes: [.font: font]).width

    override var isFlipped: Bool { true }

    /// Returns whether the gutter's width changed.
    func setLineCount(_ count: Int) -> Bool {
        lineCount = count
        let next = CodeLineNumbers.gutterWidth(lineCount: count, digitWidth: digitWidth)
        guard abs(next - width) > 0.5 else { return false }
        width = next
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage
        else { return }
        layoutManager.ensureLayout(for: container)

        // Hairline between the numbers and the code.
        let rule = NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height)
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        rule.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let right = bounds.maxX - CodeLineNumbers.trailingInset
        let length = storage.length
        // Baselines come from the fragment top plus the code font's ascender: a newline glyph
        // reports no usable location of its own, and every line shares the one monospaced font.
        let ascender = (storage.length > 0 ? storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil)?.ascender
            ?? NSFont.monospacedSystemFont(ofSize: MarkdownTextBuilder.codeSize, weight: .regular).ascender
        for (index, start) in CodeLineNumbers.lineStarts(in: storage.string).enumerated() {
            let fragment: NSRect
            if start < length {
                let glyph = layoutManager.glyphIndexForCharacter(at: start)
                fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else if layoutManager.extraLineFragmentTextContainer != nil {
                // The empty line after a trailing newline has no glyphs; its rect stands in.
                fragment = layoutManager.extraLineFragmentRect
            } else {
                continue
            }
            let baseline = fragment.minY + ascender
            let label = String(index + 1) as NSString
            let size = label.size(withAttributes: attributes)
            let origin = NSPoint(x: right - size.width, y: baseline - font.ascender)
            guard origin.y + size.height >= dirtyRect.minY, origin.y <= dirtyRect.maxY else { continue }
            label.draw(at: origin, withAttributes: attributes)
        }
    }
}
