import AppKit
import SwiftUI

struct ChatView: View {
    @Bindable var session: AppSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if session.activeTurns.isEmpty {
                        emptyState
                    }
                    ForEach(session.activeTurns) { turn in
                        MessageBubble(
                            turn: turn,
                            mermaidAsCode: session.mermaidAsCode,
                            activity: turn.status == .streaming ? session.activeActivity : nil,
                            onPreview: { session.previewAttachment = $0 }
                        )
                        .id(turn.id)
                    }
                }
                .frame(maxWidth: CueTheme.readingColumnMax)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CueTheme.Spacing.lg)
                .padding(.top, CueTheme.Spacing.md)
                .padding(.bottom, CueTheme.Spacing.lg)
            }
            .onChange(of: session.activeTurns.last?.content) { _, _ in
                if let id = session.activeTurns.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onChange(of: session.activeID) { _, _ in
                if let id = session.activeTurns.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: CueTheme.Spacing.sm) {
            CueMark(pointSize: 36)
                .padding(.bottom, CueTheme.Spacing.xs)
            Text("Cue")
                .font(.system(size: 27, weight: .medium))
            if let project = session.activeProject {
                Text("Cue will read **\(project.name)** with Codex and answer from that codebase.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(project.catalog == nil ? "Not indexed — Codex explores the tree on demand." : "Indexed \(project.catalogAt.map { $0.formatted(.relative(presentation: .named)) } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Ask anything. Listen, capture, and stay out of the way.")
                    .foregroundStyle(.secondary)
                Button {
                    session.openProjectFolder()
                } label: {
                    Label("Load project", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .cueGlass(cornerRadius: 16, interactive: true)
                .padding(.top, CueTheme.Spacing.xs)
                .help("Chat about a local codebase through the Codex CLI")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

struct MessageBubble: View {
    var turn: ChatTurn
    var mermaidAsCode: Bool
    /// Agent progress line shown before the first token arrives (Codex explore status).
    var activity: String? = nil
    var onPreview: (MessageAttachment) -> Void

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 8) {
                if !turn.attachments.isEmpty {
                    ForEach(turn.attachments) { attachment in
                        if let image = AttachmentImage.nsImage(from: attachment) {
                            Button {
                                onPreview(attachment)
                            } label: {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("View \(attachment.name)")
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
                    if turn.status == .streaming, turn.content.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(activity ?? "Thinking…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                        .padding(.vertical, 4)
                        .animation(.easeInOut(duration: 0.18), value: activity)
                    } else if turn.status == .error {
                        Label(turn.content, systemImage: "exclamationmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } else {
                        MarkdownMessageView(
                            text: turn.content,
                            mermaidAsCode: mermaidAsCode,
                            streaming: turn.status == .streaming
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if turn.status == .streaming, !turn.content.isEmpty {
                        Text("▍")
                            .foregroundStyle(.secondary)
                    }
                    if let cost = turn.costUsd, let timing = turn.timing {
                        Text("\(Pricing.formatUsd(cost)) · \(Pricing.formatLatencyPair(timeToFirstTokenMs: timing.timeToFirstTokenMs, totalMs: timing.totalMs))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if turn.role != .user { Spacer(minLength: 24) }
        }
    }
}
