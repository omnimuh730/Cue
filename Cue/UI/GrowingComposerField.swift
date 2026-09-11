import AppKit
import SwiftUI

enum ComposerFieldMetrics {
    /// Height the field should occupy for a given amount of laid-out text.
    /// One line minimum; scrolls inside once past `composerMaxLines`.
    static func viewportHeight(forUsedHeight used: CGFloat) -> CGFloat {
        let line = CueTheme.composerLineHeight
        let floor = line * CGFloat(CueTheme.composerMinLines)
        let ceiling = line * CGFloat(CueTheme.composerMaxLines)
        return min(max(ceil(used), floor), ceiling)
    }

    static func showsScroller(forUsedHeight used: CGFloat) -> Bool {
        ceil(used) > CueTheme.composerLineHeight * CGFloat(CueTheme.composerMaxLines) + 0.5
    }
}

/// Multi-line composer that grows with its text. The scroll view reports the measured text
/// height as its intrinsic size, so SwiftUI lays it out like any other view — no height
/// binding, no feedback loop.
struct GrowingComposerField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> ComposerScrollView {
        let scroll = ComposerScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .automatic
        scroll.focusRingType = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.contentView.drawsBackground = false
        scroll.scrollerStyle = .overlay

        // Explicit TextKit 1 stack: predictable `usedRect` measurement on every macOS version.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = ComposerTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.font = Coordinator.composerFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.focusRingType = .none
        textView.defaultParagraphStyle = Coordinator.paragraphStyle
        textView.typingAttributes = Coordinator.typingAttributes
        textView.minSize = NSSize(width: 0, height: CueTheme.composerMinHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        Self.applyTypingAttributes(to: textView)

        scroll.documentView = textView
        scroll.textView = textView
        context.coordinator.scrollView = scroll
        scroll.remeasure()
        return scroll
    }

    /// Height is a function of the proposed width, so SwiftUI gets an exact answer synchronously
    /// instead of treating the scroll view as freely stretchable.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ComposerScrollView, context: Context) -> CGSize? {
        let height = nsView.measure(proposedWidth: proposal.width)
        return CGSize(width: proposal.width ?? nsView.bounds.width, height: height)
    }

    func updateNSView(_ scroll: ComposerScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        guard let textView = scroll.textView else { return }
        if textView.string != text {
            let editing = textView.window?.firstResponder === textView
            let selected = textView.selectedRanges
            textView.string = text
            Self.applyTypingAttributes(to: textView)
            let limit = (text as NSString).length
            if editing {
                let valid = selected.compactMap { value -> NSValue? in
                    guard let range = value as? NSRange, NSMaxRange(range) <= limit else { return nil }
                    return NSValue(range: range)
                }
                textView.selectedRanges = valid.isEmpty ? [NSValue(range: NSRange(location: limit, length: 0))] : valid
            }
            scroll.remeasure()
        }
    }

    static func applyTypingAttributes(to textView: NSTextView) {
        textView.defaultParagraphStyle = Coordinator.paragraphStyle
        textView.typingAttributes = Coordinator.typingAttributes
        let length = textView.string.utf16.count
        guard length > 0, let storage = textView.textStorage else { return }
        storage.addAttributes(Coordinator.typingAttributes, range: NSRange(location: 0, length: length))
    }
}

final class ComposerScrollView: NSScrollView {
    weak var textView: ComposerTextView?
    /// Height last handed to SwiftUI. Only a change here triggers another layout pass.
    private var reportedHeight = CueTheme.composerMinHeight
    private var lastLayoutWidth: CGFloat = -1

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: reportedHeight)
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Lays the text out at `width` and returns the viewport height the field should occupy.
    /// Overlay scrollers never shrink the content width, so this matches what SwiftUI proposes.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 1, let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return reportedHeight
        }
        if abs(container.containerSize.width - width) > 0.5 {
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        // `usedRect` already includes the extra line fragment for empty text or a trailing newline.
        let used = layoutManager.usedRect(for: container).height
        hasVerticalScroller = ComposerFieldMetrics.showsScroller(forUsedHeight: used)
        return ComposerFieldMetrics.viewportHeight(forUsedHeight: used)
    }

    /// Called from `sizeThatFits`: the authoritative measurement for SwiftUI's proposal.
    func measure(proposedWidth: CGFloat?) -> CGFloat {
        let width = proposedWidth ?? contentSize.width
        reportedHeight = height(forWidth: width)
        return reportedHeight
    }

    /// Text changed: recompute at the current width and relayout only if the height moved.
    func remeasure() {
        let width = contentSize.width > 1 ? contentSize.width : bounds.width
        guard width > 1 else { return }
        let next = height(forWidth: width)
        if abs(next - reportedHeight) > 0.5 {
            reportedHeight = next
            invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        // Wrap width settled or changed (window resize): re-measure once per distinct width.
        let width = contentSize.width
        guard width > 1, abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        remeasure()
    }

    /// Clicks in the empty area below short text still land in the field.
    override func mouseDown(with event: NSEvent) {
        guard let textView else { return super.mouseDown(with: event) }
        textView.takeFocus()
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }
}

final class ComposerTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    /// The first click into a non-key window must both make the panel key and place the caret.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Cue's panel is non-activating and `becomesKeyOnlyIfNeeded`; take key status explicitly on
    /// click so typing works without the interview app losing activation.
    func takeFocus() {
        guard let window else { return }
        if !window.isKeyWindow { window.makeKey() }
        if window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    override func mouseDown(with event: NSEvent) {
        takeFocus()
        super.mouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        super.pasteAsPlainText(sender)
    }
}

extension GrowingComposerField {
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        weak var scrollView: ComposerScrollView?

        static let composerFont = NSFont.systemFont(ofSize: CueTheme.composerFontSize)

        static let paragraphStyle: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = CueTheme.composerLineHeight
            style.maximumLineHeight = CueTheme.composerLineHeight
            style.lineBreakMode = .byWordWrapping
            return style
        }()

        static var typingAttributes: [NSAttributedString.Key: Any] {
            [
                .font: composerFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        }

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            scrollView?.remeasure()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    return false
                }
                onSubmit()
                return true
            }
            return false
        }
    }
}
