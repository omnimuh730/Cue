import SwiftUI
import WebKit

/// Renders one ```mermaid fence as a diagram on an Excalidraw-style canvas: dot-grid paper, drag
/// to pan, pinch or ⌘-scroll to zoom toward the cursor, a zoom island in the corner, and an
/// expand button that opens the same canvas across the window.
/// Falls back to the source when Mermaid reports a parse error.
struct MermaidBlockView: View {
    var source: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.expandDiagram) private var expandDiagram
    @State private var height: CGFloat = MermaidCanvasLayout.defaultHeight
    @State private var error: String?
    @State private var hovering = false

    var body: some View {
        // A cached height means no layout jump when a diagram scrolls back into view.
        let cachedHeight = MermaidRenderCache.entry(for: MermaidRenderCache.key(source: source, theme: colorScheme == .dark ? "dark" : "neutral"))?.height
        let shownHeight = height == MermaidCanvasLayout.defaultHeight ? (cachedHeight ?? height) : height
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
                    MermaidCanvasView(source: source, mode: .inline, hovering: hovering, onHeight: { next in
                        let clamped = MermaidCanvasLayout.inlineHeight(for: next)
                        if abs(clamped - height) > 1 { height = clamped }
                    }, onError: { message in
                        error = message
                    })
                    .frame(height: shownHeight)
                    .frame(maxWidth: .infinity)
                } accessory: {
                    Button {
                        expandDiagram(source)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 20)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background(Color.primary.opacity(hovering ? 0.08 : 0), in: Capsule())
                    .opacity(hovering ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.15), value: hovering)
                    .help("Open the diagram across the window")
                    .accessibilityLabel("Expand diagram")
                }
            }
        }
        .onChange(of: source) { _, _ in
            error = nil
        }
    }
}

/// Where the block asks the chat for an expanded diagram; `RootView` supplies the overlay.
struct ExpandDiagramKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    var expandDiagram: (String) -> Void {
        get { self[ExpandDiagramKey.self] }
        set { self[ExpandDiagramKey.self] = newValue }
    }
}

/// Inline block heights, kept pure so they are unit-testable.
nonisolated enum MermaidCanvasLayout {
    /// Shown until the diagram reports what it wants.
    static let defaultHeight: CGFloat = 220
    static let minHeight: CGFloat = 180
    static let maxHeight: CGFloat = 640

    /// The page reports the height the fitted diagram wants; the block gives it that within reason.
    static func inlineHeight(for requested: CGFloat) -> CGFloat {
        guard requested.isFinite else { return defaultHeight }
        return min(max(requested.rounded(.up), minHeight), maxHeight)
    }
}

/// Zoom arithmetic for the diagram canvas, kept pure so it is unit-testable.
nonisolated enum MermaidZoom {
    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 30

    static func clamp(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(scale, minScale), maxScale)
    }

    /// ⌘-scroll: one full notch (or 200 precise points) doubles or halves the magnification.
    static func factor(forScrollDelta delta: CGFloat, precise: Bool) -> CGFloat {
        guard delta.isFinite else { return 1 }
        return pow(2, delta / (precise ? 200 : 20))
    }

    /// Screen-point pan for a scroll-wheel event. Trackpad deltas are already points and the
    /// content follows the fingers; a mouse notch is in lines, widened so a notch moves the
    /// canvas a readable amount.
    static func panPoints(scrollDeltaX dx: CGFloat, scrollDeltaY dy: CGFloat, precise: Bool) -> CGSize {
        guard dx.isFinite, dy.isFinite else { return .zero }
        let unit: CGFloat = precise ? 1 : 10
        return CGSize(width: dx * unit, height: dy * unit)
    }

    /// The percentage the zoom island shows.
    static func percent(_ scale: CGFloat) -> Int {
        guard scale.isFinite else { return 100 }
        return Int((scale * 100).rounded())
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

// MARK: - Canvas

/// The diagram canvas with its zoom island. Inline it sits in a code frame at a height the
/// diagram asked for; expanded it fills the preview overlay.
struct MermaidCanvasView: View {
    enum Mode {
        /// In the transcript: scrolling reaches the chat until the diagram is zoomed or panned.
        case inline
        /// Across the window: scrolling always pans, like Excalidraw's canvas.
        case expanded
    }

    var source: String
    var mode: Mode
    /// Whether the pointer is over the enclosing block; the island shows on hover or when zoomed.
    var hovering: Bool = true
    var onHeight: (CGFloat) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    @State private var camera = MermaidCamera()
    @State private var viewer = MermaidViewerHandle()

    var body: some View {
        MermaidWebView(source: source, mode: mode, viewer: viewer, onHeight: onHeight, onError: onError, onCamera: { next in
            camera = next
        })
        .overlay(alignment: .bottomLeading) {
            zoomIsland
                .padding(CueTheme.Spacing.xs)
                .opacity(mode == .expanded || hovering || !camera.home ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: hovering || !camera.home)
        }
        .help(mode == .inline
              ? "Pinch or ⌘-scroll to zoom. Drag to pan; scroll pans while zoomed. Double-click to fit."
              : "Pinch or ⌘-scroll to zoom. Scroll or drag to pan. Double-click to fit.")
    }

    /// Excalidraw's bottom-left island: zoom out, the percentage (click for 1:1), zoom in, fit.
    private var zoomIsland: some View {
        HStack(spacing: 0) {
            islandButton("minus", help: "Zoom out") { viewer.zoomStep(-1) }
                .disabled(camera.zoom <= MermaidZoom.minScale + 0.001)
            Button {
                viewer.resetZoom()
            } label: {
                Text("\(MermaidZoom.percent(camera.zoom))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset zoom to 100%")
            .accessibilityLabel("Zoom \(MermaidZoom.percent(camera.zoom)) percent, reset to 100 percent")
            islandButton("plus", help: "Zoom in") { viewer.zoomStep(1) }
                .disabled(camera.zoom >= MermaidZoom.maxScale - 0.001)
            Divider().frame(height: 14).padding(.horizontal, 2)
            islandButton("viewfinder", help: "Fit the whole diagram") { viewer.fit() }
        }
        .padding(.horizontal, 2)
        .cueGlass(cornerRadius: 9, interactive: true)
    }

    private func islandButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// What the page reports about its camera: the zoom and whether it rests at the fitted view.
struct MermaidCamera: Equatable {
    var zoom: CGFloat = 1
    var home = true
}

/// Lets SwiftUI controls drive the web view's camera without holding the view itself.
@MainActor
final class MermaidViewerHandle {
    weak var view: MermaidWebContentView?

    func zoomStep(_ direction: Int) { view?.run("cueViewer.zoomStep(\(direction))") }
    func resetZoom() { view?.run("cueViewer.resetZoom()") }
    func fit() { view?.run("cueViewer.fit(true)") }
}

/// WKWebView whose gestures drive the page's camera. Pinch and ⌘-scroll zoom toward the cursor,
/// smart-zoom toggles between 2× and fit, drag pans in the page itself. Plain scrolling pans in
/// the expanded view and, inline, only once the diagram has left its fitted view — otherwise the
/// chat keeps scrolling through diagrams.
final class MermaidWebContentView: WKWebView {
    var mode: MermaidCanvasView.Mode = .inline
    /// Mirrors the page's report; slightly stale is fine for deciding who gets a scroll.
    var atHome = true

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func run(_ script: String) {
        evaluateJavaScript("void \(script)") { _, _ in }
    }

    override func magnify(with event: NSEvent) {
        let point = flippedPoint(event)
        run("cueViewer.zoomAt(\(1 + event.magnification), \(point.x), \(point.y))")
    }

    override func smartMagnify(with event: NSEvent) {
        let point = flippedPoint(event)
        if atHome {
            run("cueViewer.zoomAt(2, \(point.x), \(point.y))")
        } else {
            run("cueViewer.fit(true)")
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let factor = MermaidZoom.factor(forScrollDelta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
            let point = flippedPoint(event)
            run("cueViewer.zoomAt(\(factor), \(point.x), \(point.y))")
            return
        }
        if mode == .expanded || !atHome {
            let delta = MermaidZoom.panPoints(scrollDeltaX: event.scrollingDeltaX, scrollDeltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
            run("cueViewer.panBy(\(delta.width), \(delta.height))")
            return
        }
        nextResponder?.scrollWheel(with: event)
    }

    /// Event location in the page's top-left-origin CSS space regardless of the view's `isFlipped`.
    private func flippedPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
    }
}

private struct MermaidWebView: NSViewRepresentable {
    var source: String
    var mode: MermaidCanvasView.Mode
    var viewer: MermaidViewerHandle
    var onHeight: (CGFloat) -> Void
    var onError: (String) -> Void
    var onCamera: (MermaidCamera) -> Void
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
        // The page owns zoom; WebKit's own page magnification would fight it.
        view.allowsMagnification = false
        view.mode = mode
        view.navigationDelegate = context.coordinator
        context.coordinator.view = view
        viewer.view = view
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
        coordinator.onCamera = onCamera
        view.mode = mode
        viewer.view = view
        let theme = colorScheme == .dark ? "dark" : "neutral"
        let key = MermaidRenderCache.key(source: source, theme: theme)
        guard coordinator.pendingKey != key else { return }
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
        weak var view: MermaidWebContentView?
        var pendingKey: String?
        var pendingSource = ""
        var pendingTheme = "neutral"
        var onHeight: ((CGFloat) -> Void)?
        var onError: ((String) -> Void)?
        var onCamera: ((MermaidCamera) -> Void)?
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
                    let clamped = MermaidCanvasLayout.inlineHeight(for: CGFloat(height))
                    if let key = renderedKey { MermaidRenderCache.store(key, height: clamped) }
                    onHeight?(CGFloat(height))
                }
            case "svg":
                if let key = renderedKey, let svg = body["svg"] as? String {
                    MermaidRenderCache.store(key, svg: svg)
                }
            case "camera":
                let zoom = CGFloat((body["zoom"] as? Double) ?? 1)
                let home = (body["home"] as? Bool) ?? true
                view?.atHome = home
                onCamera?(MermaidCamera(zoom: zoom, home: home))
            case "error":
                onError?((body["message"] as? String) ?? "Mermaid could not render this diagram.")
            default:
                break
            }
        }
    }
}

// MARK: - Expanded overlay

/// The diagram across the window: the same canvas with scrolling free to pan, like Excalidraw.
struct MermaidPreviewOverlay: View {
    var source: String
    var onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 10)
                canvas
            }
            .padding(16)
            .cueGlass(cornerRadius: 18, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
            .padding(28)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Mermaid diagram")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Mermaid")
                .font(.system(size: 13, weight: .semibold))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy source", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .help("Copy the diagram source")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var canvas: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return MermaidCanvasView(source: source, mode: .expanded, onError: { error = $0 })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // Flat fill for diagram contrast, the same exception the code frame makes.
                shape.fill(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : 0.7))
            }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
            .clipShape(shape)
    }
}
