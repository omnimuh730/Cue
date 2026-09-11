import SwiftUI

struct MarkdownMessageView: View {
    var text: String
    var mermaidAsCode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let value):
                    Text(parse(value))
                        .font(.system(size: 15.5))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                case .mermaid(let value):
                    if mermaidAsCode {
                        Text(value)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        MermaidBlockView(source: value)
                            .frame(minHeight: 180)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Block {
        case markdown(String)
        case mermaid(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var remaining = text
        while let start = remaining.range(of: "```mermaid") {
            let before = String(remaining[..<start.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.markdown(before))
            }
            remaining = String(remaining[start.upperBound...])
            if let end = remaining.range(of: "```") {
                result.append(.mermaid(String(remaining[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)))
                remaining = String(remaining[end.upperBound...])
            } else {
                result.append(.mermaid(remaining))
                remaining = ""
            }
        }
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.markdown(remaining))
        }
        return result
    }

    private func parse(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}
