import SwiftUI
import WebKit

/// Renders one ```mermaid fence as a diagram, sized to its content.
/// Falls back to the source when Mermaid reports a parse error.
struct MermaidBlockView: View {
    var source: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 160
    @State private var error: String?
    @State private var zoom = MermaidZoomPan()

    var body: some View {
        // A cached height means no layout jump when a diagram scrolls back into view.
        let cachedHeight = MermaidRenderCache.entry(for: MermaidRenderCache.key(source: source, theme: colorScheme == .dark ? "dark" : "neutral"))?.height
        let shownHeight = height == 160 ? (cachedHeight ?? height) : height
        Group {
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    MermaidSourceView(source: source)
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                MermaidWebView(source: source, onHeight: { next in
                    if abs(next - height) > 1 { height = next }
                }, onError: { message in
                    error = message
                })
                .frame(height: min(max(shownHeight, 80), 900))
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(zoom.scale)
                .offset(zoom.offset)
                .clipped()
                .overlay {
                    GeometryReader { geo in
                        MermaidZoomCatcher(state: $zoom, size: geo.size)
                            .onChange(of: geo.size) { _, size in
                                zoom.clamp(in: size)
                            }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if zoom.scale > 1.01 {
                        Text("\(Int((zoom.scale * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, CueTheme.Spacing.xs)
                            .padding(.vertical, CueTheme.Spacing.xxs)
                            .background(.thinMaterial, in: Capsule())
                            .padding(CueTheme.Spacing.xs)
                            .allowsHitTesting(false)
                    }
                }
                .help("Pinch or ⌘-scroll to zoom. Drag to pan when zoomed. Double-click to reset.")
            }
        }
        .onChange(of: source) { _, _ in
            error = nil
            zoom.reset()
        }
    }
}

/// Pinch / ⌘-scroll zoom with drag pan once the scaled diagram is larger than its frame.
struct MermaidZoomPan: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 5

    var canPan: Bool { scale > 1.001 }

    mutating func reset() {
        scale = 1
        offset = .zero
    }

    mutating func zoom(by factor: CGFloat, toward point: CGPoint, in size: CGSize) {
        let old = scale
        guard old > 0, factor.isFinite, factor > 0 else { return }
        let next = min(max(old * factor, Self.minScale), Self.maxScale)
        guard abs(next - old) > 0.0001 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let cursor = CGSize(width: point.x - center.x, height: point.y - center.y)
        let ratio = next / old
        offset = CGSize(
            width: cursor.width - (cursor.width - offset.width) * ratio,
            height: cursor.height - (cursor.height - offset.height) * ratio
        )
        scale = next
        clamp(in: size)
    }

    mutating func pan(by delta: CGSize, in size: CGSize) {
        guard canPan else { return }
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        clamp(in: size)
    }

    mutating func clamp(in size: CGSize) {
        scale = min(max(scale, Self.minScale), Self.maxScale)
        if scale <= 1.001 {
            scale = 1
            offset = .zero
            return
        }
        guard size.width > 0, size.height > 0 else { return }
        let extraX = max(0, size.width * (scale - 1) / 2)
        let extraY = max(0, size.height * (scale - 1) / 2)
        offset.width = min(max(offset.width, -extraX), extraX)
        offset.height = min(max(offset.height, -extraY), extraY)
    }
}

/// Sits above the web view so pinch, ⌘-scroll, and drag work even while Cue is a nonactivating panel.
private struct MermaidZoomCatcher: NSViewRepresentable {
    @Binding var state: MermaidZoomPan
    var size: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(state: $state, size: size)
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        context.coordinator.state = $state
        context.coordinator.size = size
        view.coordinator = context.coordinator
        view.window?.invalidateCursorRects(for: view)
    }

    final class Coordinator {
        var state: Binding<MermaidZoomPan>
        var size: CGSize
        var lastPoint: CGPoint?

        init(state: Binding<MermaidZoomPan>, size: CGSize) {
            self.state = state
            self.size = size
        }

        func apply(_ body: (inout MermaidZoomPan) -> Void) {
            var next = state.wrappedValue
            body(&next)
            state.wrappedValue = next
        }
    }

    final class CatcherView: NSView {
        var coordinator: Coordinator?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = .clear
        }

        required init?(coder: NSCoder) { nil }

        override var isOpaque: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func resetCursorRects() {
            if coordinator?.state.wrappedValue.canPan == true {
                addCursorRect(bounds, cursor: .openHand)
            }
        }

        override func magnify(with event: NSEvent) {
            let target = point(of: event)
            let size = viewportSize
            coordinator?.apply { $0.zoom(by: 1 + event.magnification, toward: target, in: size) }
        }

        override func smartMagnify(with event: NSEvent) {
            let target = point(of: event)
            let size = viewportSize
            coordinator?.apply { zoom in
                if zoom.canPan {
                    zoom.reset()
                } else {
                    zoom.zoom(by: 2, toward: target, in: size)
                }
            }
        }

        override func scrollWheel(with event: NSEvent) {
            let command = event.modifierFlags.contains(.command)
            if command {
                let divisor: CGFloat = event.hasPreciseScrollingDeltas ? 200 : 20
                let factor = pow(2, event.scrollingDeltaY / divisor)
                let target = point(of: event)
                let size = viewportSize
                coordinator?.apply { $0.zoom(by: factor, toward: target, in: size) }
                return
            }
            if coordinator?.state.wrappedValue.canPan == true {
                let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
                var next = coordinator?.state.wrappedValue ?? MermaidZoomPan()
                let before = next.offset
                next.pan(by: delta, in: viewportSize)
                if next.offset != before {
                    coordinator?.state.wrappedValue = next
                    return
                }
            }
            super.scrollWheel(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                coordinator?.lastPoint = nil
                withAnimation(.easeOut(duration: 0.18)) {
                    coordinator?.apply { $0.reset() }
                }
                window?.invalidateCursorRects(for: self)
                return
            }
            guard coordinator?.state.wrappedValue.canPan == true else { return }
            coordinator?.lastPoint = point(of: event)
            NSCursor.closedHand.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let last = coordinator?.lastPoint else { return }
            let current = point(of: event)
            let size = viewportSize
            coordinator?.lastPoint = current
            coordinator?.apply {
                $0.pan(by: CGSize(width: current.x - last.x, height: current.y - last.y), in: size)
            }
        }

        override func mouseUp(with event: NSEvent) {
            coordinator?.lastPoint = nil
            window?.invalidateCursorRects(for: self)
        }

        private func point(of event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            return CGPoint(x: local.x, y: bounds.height - local.y)
        }

        private var viewportSize: CGSize {
            coordinator?.size ?? bounds.size
        }
    }
}

struct MermaidSourceView: View {
    var source: String

    var body: some View {
        Text(source)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct MermaidWebView: NSViewRepresentable {
    var source: String
    var onHeight: (CGFloat) -> Void
    var onError: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Shared in-memory store: one process/cache group for every diagram instead of one each.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()
    private static let hostURL = Bundle.main.url(forResource: "mermaid-host", withExtension: "html")

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore
        config.userContentController.add(context.coordinator, name: Coordinator.channel)
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = false
        view.navigationDelegate = context.coordinator
        if let host = Self.hostURL {
            view.loadFileURL(host, allowingReadAccessTo: host.deletingLastPathComponent())
        } else {
            context.coordinator.onError?("Mermaid renderer is missing from this build.")
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onHeight = onHeight
        coordinator.onError = onError
        let theme = colorScheme == .dark ? "dark" : "neutral"
        let key = MermaidRenderCache.key(source: source, theme: theme)
        guard coordinator.pendingKey != key else { return }
        coordinator.pendingKey = key
        coordinator.pendingSource = source
        coordinator.pendingTheme = theme
        if let cached = MermaidRenderCache.entry(for: key)?.height { onHeight(cached) }
        coordinator.renderIfReady(in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
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
