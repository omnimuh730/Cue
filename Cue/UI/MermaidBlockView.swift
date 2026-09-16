import SwiftUI
import WebKit

/// Renders one ```mermaid fence as a diagram, sized to its content.
/// Falls back to the source when Mermaid reports a parse error.
struct MermaidBlockView: View {
    var source: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 160
    @State private var error: String?
    @State private var magnification: CGFloat = 1
    @State private var hovering = false

    var body: some View {
        // A cached height means no layout jump when a diagram scrolls back into view.
        let cachedHeight = MermaidRenderCache.entry(for: MermaidRenderCache.key(source: source, theme: colorScheme == .dark ? "dark" : "neutral"))?.height
        let shownHeight = height == 160 ? (cachedHeight ?? height) : height
        Group {
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    CodeBlockView(language: "mermaid", source: source)
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                // Same chrome as a code block, so the diagram's source is one click away.
                CodeBlockFrame(title: "Mermaid", source: source, hovering: $hovering) {
                    diagram(height: shownHeight)
                }
            }
        }
        .onChange(of: source) { _, _ in
            error = nil
            magnification = 1
        }
    }

    private func diagram(height shownHeight: CGFloat) -> some View {
        MermaidWebView(source: source, onHeight: { next in
            if abs(next - height) > 1 { height = next }
        }, onError: { message in
            error = message
        }, onMagnification: { next in
            magnification = next
        })
        .frame(height: min(max(shownHeight, 80), 900))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomTrailing) {
            if magnification > 1.01 {
                Text("\(Int((magnification * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, CueTheme.Spacing.xs)
                    .padding(.vertical, CueTheme.Spacing.xxs)
                    .background(.thinMaterial, in: Capsule())
                    .padding(CueTheme.Spacing.xs)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: magnification > 1.01)
        .help("Pinch or ⌘-scroll to zoom. Scroll or drag to pan when zoomed. Double-click to reset.")
    }
}

/// Zoom arithmetic for the diagram web view, kept pure so it is unit-testable.
nonisolated enum MermaidZoom {
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 5

    static func clamp(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return minScale }
        return min(max(scale, minScale), maxScale)
    }

    /// ⌘-scroll: one full notch (or 200 precise points) doubles or halves the magnification.
    static func factor(forScrollDelta delta: CGFloat, precise: Bool) -> CGFloat {
        guard delta.isFinite else { return 1 }
        return pow(2, delta / (precise ? 200 : 20))
    }

    /// Converts a scroll-wheel delta into a CSS-pixel `window.scrollBy` at the given magnification.
    /// AppKit's natural scrolling reports positive deltas when content should move down/right,
    /// which is a negative page scroll.
    static func panDelta(scrollDeltaX dx: CGFloat, scrollDeltaY dy: CGFloat, magnification: CGFloat) -> CGSize {
        let scale = max(magnification, 0.001)
        return CGSize(width: -dx / scale, height: -dy / scale)
    }

    /// Page scroll position that keeps the content under the cursor while dragging.
    /// `start`/`current` are in a top-left-origin (flipped) view space; the content follows the
    /// cursor, so the page scrolls opposite to the drag, in CSS px at the current magnification.
    static func dragScrollTarget(anchorScroll: CGPoint, start: CGPoint, current: CGPoint, magnification: CGFloat) -> CGPoint {
        let scale = max(magnification, 0.001)
        return CGPoint(
            x: max(0, anchorScroll.x - (current.x - start.x) / scale),
            y: max(0, anchorScroll.y - (current.y - start.y) / scale)
        )
    }
}

struct MermaidSourceView: View {
    var source: String

    var body: some View {
        SelectableTextView(text: MarkdownTextBuilder.plain(source, size: 13).monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension NSAttributedString {
    func monospaced() -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: self)
        copy.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: MarkdownTextBuilder.codeSize, weight: .regular), range: NSRange(location: 0, length: copy.length))
        return copy
    }
}

/// Rendered SVG and measured height per (theme, source) so re-opening a chat skips the
/// Mermaid parse and never jumps from a placeholder height.
@MainActor
enum MermaidRenderCache {
    struct Entry {
        var svg: String?
        var height: CGFloat?
    }

    private static var entries: [String: Entry] = [:]
    private static var order: [String] = []
    private static let limit = 120

    static func key(source: String, theme: String) -> String { "\(theme)\u{0}\(source)" }

    static func entry(for key: String) -> Entry? { entries[key] }

    static func store(_ key: String, svg: String? = nil, height: CGFloat? = nil) {
        var entry = entries[key] ?? Entry()
        if let svg { entry.svg = svg }
        if let height { entry.height = height }
        if entries[key] == nil {
            order.append(key)
            if order.count > limit, let oldest = order.first {
                order.removeFirst()
                entries[oldest] = nil
            }
        }
        entries[key] = entry
    }
}

/// WKWebView with page magnification exposed as the diagram's zoom. Pinch and smart-zoom are
/// native; ⌘-scroll zooms toward the cursor, scroll/drag pan while zoomed, double-click resets.
/// Unzoomed scrolls are handed up so the chat keeps scrolling through diagrams.
final class MermaidWebContentView: WKWebView {
    var onMagnification: ((CGFloat) -> Void)?
    /// Drag-pan state: where the drag began and what the page scroll was at that moment.
    private var dragStart: CGPoint?
    private var dragAnchorScroll: CGPoint?
    private var dragLatest: CGPoint?

    var isZoomed: Bool { magnification > 1.001 }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        clampAndReport()
    }

    override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
        clampAndReport()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let factor = MermaidZoom.factor(forScrollDelta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
            setMagnification(MermaidZoom.clamp(magnification * factor), centeredAt: convert(event.locationInWindow, from: nil))
            clampAndReport()
            return
        }
        if isZoomed {
            let delta = MermaidZoom.panDelta(scrollDeltaX: event.scrollingDeltaX, scrollDeltaY: event.scrollingDeltaY, magnification: magnification)
            scrollPage(by: delta)
            return
        }
        nextResponder?.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            setMagnification(1, centeredAt: convert(event.locationInWindow, from: nil))
            clampAndReport()
            return
        }
        guard isZoomed else { return super.mouseDown(with: event) }
        let start = flippedPoint(event)
        dragStart = start
        dragLatest = start
        dragAnchorScroll = nil
        NSCursor.closedHand.set()
        // Anchor on the page's actual scroll offset so the content stays glued to the cursor.
        evaluateJavaScript("[window.scrollX, window.scrollY]") { [weak self] value, _ in
            guard let self, dragStart == start, let pair = value as? [Double], pair.count == 2 else { return }
            dragAnchorScroll = CGPoint(x: pair[0], y: pair[1])
            if let latest = dragLatest { applyDrag(to: latest) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return super.mouseDragged(with: event) }
        let current = flippedPoint(event)
        dragLatest = current
        applyDrag(to: current)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return super.mouseUp(with: event) }
        dragStart = nil
        dragLatest = nil
        dragAnchorScroll = nil
        window?.invalidateCursorRects(for: self)
    }

    private func applyDrag(to point: CGPoint) {
        guard let start = dragStart, let anchor = dragAnchorScroll else { return }
        let target = MermaidZoom.dragScrollTarget(anchorScroll: anchor, start: start, current: point, magnification: magnification)
        evaluateJavaScript("window.scrollTo(\(target.x), \(target.y))") { _, _ in }
    }

    /// Event location in a top-left-origin space regardless of the view's `isFlipped`.
    private func flippedPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
    }

    override func resetCursorRects() {
        if isZoomed { addCursorRect(bounds, cursor: .openHand) }
    }

    private func scrollPage(by delta: CGSize) {
        guard delta.width.isFinite, delta.height.isFinite else { return }
        evaluateJavaScript("window.scrollBy(\(delta.width), \(delta.height))") { _, _ in }
    }

    private func clampAndReport() {
        let clamped = MermaidZoom.clamp(magnification)
        if abs(clamped - magnification) > 0.001 {
            setMagnification(clamped, centeredAt: CGPoint(x: bounds.midX, y: bounds.midY))
        }
        if !isZoomed {
            evaluateJavaScript("window.scrollTo(0, 0)") { _, _ in }
        }
        window?.invalidateCursorRects(for: self)
        onMagnification?(magnification)
    }
}

private struct MermaidWebView: NSViewRepresentable {
    var source: String
    var onHeight: (CGFloat) -> Void
    var onError: (String) -> Void
    var onMagnification: (CGFloat) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Shared in-memory store: one process/cache group for every diagram instead of one each.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()
    private static let hostURL = Bundle.main.url(forResource: "mermaid-host", withExtension: "html")

    func makeNSView(context: Context) -> MermaidWebContentView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore
        config.userContentController.add(context.coordinator, name: Coordinator.channel)
        let view = MermaidWebContentView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = true
        view.onMagnification = onMagnification
        view.navigationDelegate = context.coordinator
        if let host = Self.hostURL {
            view.loadFileURL(host, allowingReadAccessTo: host.deletingLastPathComponent())
        } else {
            context.coordinator.onError?("Mermaid renderer is missing from this build.")
        }
        return view
    }

    func updateNSView(_ view: MermaidWebContentView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onHeight = onHeight
        coordinator.onError = onError
        view.onMagnification = onMagnification
        let theme = colorScheme == .dark ? "dark" : "neutral"
        let key = MermaidRenderCache.key(source: source, theme: theme)
        guard coordinator.pendingKey != key else { return }
        if coordinator.pendingKey != nil, view.isZoomed {
            view.setMagnification(1, centeredAt: .zero)
            onMagnification(1)
        }
        coordinator.pendingKey = key
        coordinator.pendingSource = source
        coordinator.pendingTheme = theme
        if let cached = MermaidRenderCache.entry(for: key)?.height { onHeight(cached) }
        coordinator.renderIfReady(in: view)
    }

    static func dismantleNSView(_ view: MermaidWebContentView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.channel)
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let channel = "cueMermaid"
        var pendingKey: String?
        var pendingSource = ""
        var pendingTheme = "neutral"
        var onHeight: ((CGFloat) -> Void)?
        var onError: ((String) -> Void)?
        private var ready = false
        private var renderedKey: String?

        func renderIfReady(in view: WKWebView) {
            guard ready, let key = pendingKey, renderedKey != key else { return }
            renderedKey = key
            let cached = MermaidRenderCache.entry(for: key)?.svg
            guard let sourceJSON = Self.json(pendingSource), let themeJSON = Self.json(pendingTheme),
                  let cachedJSON = Self.json(cached ?? "")
            else { return }
            view.evaluateJavaScript("void window.cueRender(\(sourceJSON), \(themeJSON), \(cachedJSON))") { _, _ in }
        }

        private static func json(_ value: String) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]) ,
                  let text = String(data: data, encoding: .utf8)
            else { return nil }
            // Encoded as a one-element array; strip the brackets to get a JS string literal.
            return String(text.dropFirst().dropLast())
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                if let view = message.webView { renderIfReady(in: view) }
            case "size":
                if let height = body["height"] as? Double, height > 0 {
                    if let key = renderedKey { MermaidRenderCache.store(key, height: CGFloat(height)) }
                    onHeight?(CGFloat(height))
                }
            case "svg":
                if let key = renderedKey, let svg = body["svg"] as? String {
                    MermaidRenderCache.store(key, svg: svg)
                }
            case "error":
                onError?((body["message"] as? String) ?? "Mermaid could not render this diagram.")
            default:
                break
            }
        }
    }
}
