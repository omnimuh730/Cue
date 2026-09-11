import SwiftUI
import WebKit

/// Renders one ```mermaid fence as a diagram, sized to its content.
/// Falls back to the source when Mermaid reports a parse error.
struct MermaidBlockView: View {
    var source: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 160
    @State private var error: String?

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
            }
        }
        .onChange(of: source) { _, _ in error = nil }
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
        view.allowsMagnification = true
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
