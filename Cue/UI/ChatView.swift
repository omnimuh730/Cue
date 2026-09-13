import AppKit
import SwiftUI

/// Holds scroll-follow state outside SwiftUI so geometry ticks do not rebuild the transcript.
private final class ChatScrollFollowBox {
    var follow = ChatScrollFollow()
}

struct ChatView: View {
    @Bindable var session: AppSession
    @State private var followBox = ChatScrollFollowBox()

    private static let bottomAnchor = "chat-bottom"

    var body: some View {
        let messages = session.activeMessages
        Group {
            if messages.isEmpty {
                emptyState
            } else {
                transcript
            }
        }
        // Never wait for the empty-hero letter cascade (or its removal) before a send lands.
        .animation(nil, value: messages.isEmpty)
    }

    private var emptyState: some View {
        GeometryReader { geo in
            ScrollView {
                EmptyChatView(
                    project: session.activeProject,
                    onProjectSettings: {
                        if let id = session.activeProject?.identifier {
                            session.projectSettingsID = id
                        }
                    },
                    onNewProject: { session.newProjectPromptOpen = true },
                    onOpenCodeFolder: { session.openProjectFolder() }
                )
                .frame(maxWidth: CueTheme.readingColumnMax)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .padding(.horizontal, CueTheme.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(session.activeMessages, id: \.identifier) { message in
                        MessageBubble(
                            message: message,
                            mermaidAsCode: session.mermaidAsCode,
                            activity: session.activeActivity,
                            onPreview: { session.previewAttachment = $0 }
                        )
                        .id(message.identifier)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .frame(maxWidth: CueTheme.readingColumnMax)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CueTheme.Spacing.lg)
                .padding(.top, CueTheme.Spacing.md)
                .padding(.bottom, CueTheme.Spacing.lg)
            }
            .onScrollGeometryChange(for: ChatScrollSnapshot.self) { geometry in
                ChatScrollSnapshot(
                    contentHeight: geometry.contentSize.height,
                    visibleMaxY: geometry.visibleRect.maxY
                )
            } action: { _, snapshot in
                if followBox.follow.apply(snapshot) {
                    scrollToLatest(proxy)
                }
            }
            .onChange(of: session.activeMessages.count) { previous, next in
                if next > previous {
                    followBox.follow.jumpToLatest()
                }
                scrollToLatest(proxy)
            }
            .onChange(of: session.activeID) { _, _ in
                followBox.follow.jumpToLatest()
                scrollToLatest(proxy)
            }
            .onAppear {
                followBox.follow.jumpToLatest()
                scrollToLatest(proxy)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard followBox.follow.shouldFollow else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }
}

/// One chat message. Reads the SwiftData `Message` directly so only this bubble re-renders when
/// its content streams; the parent list is untouched until a message is added or removed.
struct MessageBubble: View {
    var message: Message
    var mermaidAsCode: Bool
    /// Agent progress line shown before the first token arrives (Codex explore status).
    var activity: String? = nil
    var onPreview: (MessageAttachment) -> Void

    @State private var hovering = false
    @State private var copied = false

    private var role: MessageRole { message.role }
    private var status: MessageStatus? { message.status }
    private var attachments: [MessageAttachment] { message.attachments }

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            VStack(alignment: role == .user ? .trailing : .leading, spacing: 8) {
                if !attachments.isEmpty {
                    ForEach(attachments) { attachment in
                        Button {
                            onPreview(attachment)
                        } label: {
                            if let image = AttachmentImage.nsImage(from: attachment) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                DocumentChipLabel(attachment: attachment)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("View \(attachment.name)")
                    }
                }
                if role == .user {
                    SelectableTextView(text: MarkdownTextBuilder.plain(message.content))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    copyRow
                } else {
                    if status == .streaming, message.content.isEmpty {
                        HStack(spacing: 8) {
                            CueMarkSpin(pointSize: 16, spinning: true, style: .busy)
                            Text(activity ?? "Thinking…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                        .padding(.vertical, 4)
                        .animation(.easeInOut(duration: 0.18), value: activity)
                    } else if status == .error {
                        Label(message.content, systemImage: "exclamationmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } else {
                        MarkdownMessageView(
                            text: message.content,
                            mermaidAsCode: mermaidAsCode,
                            streaming: status == .streaming
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if status == .streaming, !message.content.isEmpty {
                        CueMarkSpin(pointSize: 13, spinning: true, style: .busy)
                    }
                    if status != .streaming {
                        HStack(spacing: 10) {
                            if let cost = message.costUsd, let timing = message.timing {
                                Text("\(Pricing.formatUsd(cost)) · \(Pricing.formatLatencyPair(timeToFirstTokenMs: timing.timeToFirstTokenMs, totalMs: timing.totalMs))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            copyRow
                        }
                    }
                }
            }
            if role != .user { Spacer(minLength: 24) }
        }
        .background { HoverRegion { hovering = $0 } }
    }

    /// Copies the message as plain text. Revealed on hover so the reading column stays quiet.
    private var copyRow: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(hovering ? 0.06 : 0), in: Capsule())
        .opacity(hovering || copied ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hovering || copied)
        .help("Copy message text")
        .accessibilityLabel("Copy message")
    }
}
