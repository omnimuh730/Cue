import AppKit
import SwiftUI

struct ChatView: View {
    @Bindable var session: AppSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if session.activeTurns.isEmpty {
                        VStack(spacing: CueTheme.Spacing.sm) {
                            CueMark(pointSize: 36)
                                .padding(.bottom, CueTheme.Spacing.xs)
                            Text("Cue")
                                .font(.system(size: 27, weight: .medium))
                            Text("Ask anything. Listen, capture, and stay out of the way.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                    ForEach(session.activeTurns) { turn in
                        MessageBubble(turn: turn, mermaidAsCode: session.mermaidAsCode)
                            .id(turn.id)
                    }
                }
                .frame(maxWidth: CueTheme.readingColumnMax)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CueTheme.Spacing.lg)
                .padding(.vertical, CueTheme.Spacing.lg)
            }
            .onChange(of: session.activeTurns.last?.content) { _, _ in
                if let id = session.activeTurns.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}

struct MessageBubble: View {
    var turn: ChatTurn
    var mermaidAsCode: Bool

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 8) {
                if !turn.attachments.isEmpty {
                    ForEach(turn.attachments) { attachment in
                        if let data = Data(base64Encoded: attachment.dataURL.components(separatedBy: ",").last ?? ""),
                           let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                if turn.role == .user {
                    Text(turn.content)
                        .font(.system(size: 15, weight: .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    MarkdownMessageView(text: turn.content, mermaidAsCode: mermaidAsCode)
                    if turn.status == .streaming {
                        Text("▍")
                            .foregroundStyle(.secondary)
                    }
                    if let cost = turn.costUsd, let timing = turn.timing {
                        Text("\(Pricing.formatUsd(cost)) · \(Pricing.formatLatencyPair(timeToFirstTokenMs: timing.timeToFirstTokenMs, totalMs: timing.totalMs))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if turn.status == .error {
                        Text(turn.content)
                            .foregroundStyle(.red)
                    }
                }
            }
            if turn.role != .user { Spacer(minLength: 24) }
        }
    }
}
