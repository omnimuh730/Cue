import SwiftUI
import WebKit

struct MermaidBlockView: NSViewRepresentable {
    var source: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let html = """
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{margin:0;background:transparent;color:#222;font-family:-apple-system}</style>
        <script type="module">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
        mermaid.initialize({ startOnLoad: false, theme: 'neutral' });
        mermaid.render('cue', `\(escaped)`).then(({svg}) => { document.body.innerHTML = svg; });
        </script></head><body></body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
}

struct VirtualCursorOverlay: View {
    var state: RemoteCursorState

    var body: some View {
        Circle()
            .strokeBorder(.white, lineWidth: 2)
            .background(Circle().fill(Color.accentColor.opacity(0.85)))
            .frame(width: 14, height: 14)
            .position(x: state.x, y: state.y)
            .allowsHitTesting(false)
    }
}
