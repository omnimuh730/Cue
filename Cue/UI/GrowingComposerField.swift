import AppKit
import SwiftUI

struct GrowingComposerField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .automatic
        scroll.focusRingType = .none

        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude)
        textView.font = Coordinator.composerFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.focusRingType = .none
        textView.typingAttributes = Coordinator.typingAttributes
        textView.string = text
        textView.minSize = NSSize(width: 0, height: CueTheme.composerMinHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = textView
        context.coordinator.scrollView = scroll
        context.coordinator.recalculateHeight(of: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.height = $height
        context.coordinator.onSubmit = onSubmit
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.typingAttributes = Coordinator.typingAttributes
            if textView.window?.firstResponder == textView {
                textView.moveToEndOfDocument(nil)
            }
        }
        context.coordinator.recalculateHeight(of: textView)
    }
}

final class ComposerTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: CueTheme.composerMinHeight)
    }

    override func paste(_ sender: Any?) {
        super.pasteAsPlainText(sender)
    }
}

extension GrowingComposerField {
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var height: Binding<CGFloat>
        var onSubmit: () -> Void
        weak var scrollView: NSScrollView?

        static let composerFont = NSFont.systemFont(ofSize: CueTheme.composerFontSize)

        static var typingAttributes: [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.5
            style.lineBreakMode = .byWordWrapping
            return [
                .font: composerFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style
            ]
        }

        init(text: Binding<String>, height: Binding<CGFloat>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.height = height
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            recalculateHeight(of: textView)
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

        func recalculateHeight(of textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
                return
            }
            let width = textView.bounds.width > 1 ? textView.bounds.width : (scrollView?.contentSize.width ?? 300)
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
            let next = min(max(ceil(used), CueTheme.composerMinHeight), CueTheme.composerMaxHeight)
            scrollView?.hasVerticalScroller = next >= CueTheme.composerMaxHeight - 0.5
            guard abs(height.wrappedValue - next) > 0.5 else { return }
            DispatchQueue.main.async { [height] in
                if abs(height.wrappedValue - next) > 0.5 {
                    height.wrappedValue = next
                }
            }
        }
    }
}
