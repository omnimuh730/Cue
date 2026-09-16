import AppKit
import SwiftUI

/// Sources a web-search answer cited, as numbered chips under the text. Five show by default;
/// the rest sit behind a "+N" chip so a heavily sourced answer does not push the next turn down.
struct CitationRow: View {
    var citations: [Citation]

    @State private var expanded = false

    private static let collapsedCount = 5

    private var shown: [Citation] {
        expanded ? citations : Array(citations.prefix(Self.collapsedCount))
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.element.url) { item in
                chip(index: item.offset + 1, citation: item.element)
            }
            if citations.count > Self.collapsedCount, !expanded {
                Button {
                    expanded = true
                } label: {
                    Text("+\(citations.count - Self.collapsedCount) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show every source")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sources")
    }

    private func chip(index: Int, citation: Citation) -> some View {
        Button {
            if let url = URL(string: citation.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 5) {
                Text("\(index)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16, height: 16)
                    .background(Color.accentColor.opacity(0.14), in: Circle())
                Text(citation.host)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if citation.displayTitle != citation.host {
                    Text(citation.displayTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 180, alignment: .leading)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .frame(height: 24)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(citation.url)
        .accessibilityLabel("Source \(index): \(citation.displayTitle)")
    }
}

/// Wraps its children onto as many rows as the width needs, like inline text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = place(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
