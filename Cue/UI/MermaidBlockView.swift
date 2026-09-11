import SwiftUI
import WebKit

/// Renders one ```mermaid fence as a diagram, sized to its content.
/// Falls back to the source when Mermaid reports a parse error.
struct MermaidBlockView: View {
    var source: String
    @State private var height: CGFloat = 160
    @State private var error: String?

    var body: some View {
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
                .frame(height: min(max(height, 80), 900))
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

private struct MermaidWebView: NSViewRepresentable {
    var source: String
    var onHeight: (CGFloat) -> Void
    var onError: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// One in-memory store for every diagram so the Mermaid module is fetched from the CDN once
    /// per launch instead of once per block.
    private static let dataStore = WKWebsiteDataStore.nonPersistent()

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore
        config.userContentController.add(context.coordinator, name: Coordinator.channel)
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = true
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeight = onHeight
        context.coordinator.onError = onError
        let theme = colorScheme == .dark ? "dark" : "neutral"
        let key = "\(theme)\u{0}\(source)"
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key
        view.loadHTMLString(Self.html(source: source, theme: theme), baseURL: nil)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.channel)
    }

    /// Mermaid's `render` sanitizes its SVG with DOMPurify. Under WebKit that pass drops the
    /// root `id`, so the `#id …` rules in the embedded stylesheet never match and every path
    /// falls back to `fill: black`. Re-applying the id after injection restores the theme.
    private static func html(source: String, theme: String) -> String {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return """
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
          body { font-family: -apple-system, system-ui, sans-serif; }
          svg { display: block; max-width: 100%; height: auto; }
        </style>
        <script type="module">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
        const post = (payload) => window.webkit?.messageHandlers?.\(Coordinator.channel)?.postMessage(payload);
        const report = () => {
          const svg = document.body.querySelector('svg');
          if (!svg) return;
          post({ type: 'size', height: Math.ceil(svg.getBoundingClientRect().height) });
        };
        mermaid.initialize({
          startOnLoad: false,
          securityLevel: 'strict',
          theme: '\(theme)',
          fontFamily: '-apple-system, system-ui, sans-serif',
          flowchart: { useMaxWidth: true, htmlLabels: true }
        });
        try {
          const { svg } = await mermaid.render('cue', `\(escaped)`);
          document.body.innerHTML = svg;
          const root = document.body.querySelector('svg');
          if (root) root.id = 'cue';
          report();
          new ResizeObserver(report).observe(document.body);
        } catch (error) {
          post({ type: 'error', message: String(error?.message ?? error).split('\\n')[0] });
        }
        </script></head><body></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let channel = "cueMermaid"
        var lastKey: String?
        var onHeight: ((CGFloat) -> Void)?
        var onError: ((String) -> Void)?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "size":
                if let height = body["height"] as? Double, height > 0 {
                    onHeight?(CGFloat(height))
                }
            case "error":
                onError?((body["message"] as? String) ?? "Mermaid could not render this diagram.")
            default:
                break
            }
        }
    }
}
