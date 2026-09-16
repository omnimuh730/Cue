import AppKit
import SwiftUI

/// Holds scroll-follow state outside SwiftUI so geometry ticks do not rebuild the transcript.
private final class ChatScrollFollowBox {
    var follow = ChatScrollFollow()
}

struct ChatView: View {
    @Bindable var session: AppSession
    @State private var followBox = ChatScrollFollowBox()
    /// Older turns beyond `historyWindow` stay out of the layout until asked for.
    @State private var historyExpanded = false

    private static let topAnchor = "chat-top"
    private static let bottomAnchor = "chat-bottom"
    /// Turns laid out eagerly. Every bubble in the window is a live text view, so this caps the
    /// cost of opening a long thread; anything older is one click away.
    static let historyWindow = 80

    private var readingOrder: ReadingOrder { session.settings.readingOrder }

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
        let all = session.activeMessages
        let hidden = historyExpanded ? 0 : max(0, all.count - Self.historyWindow)
        let shown = readingOrder.arrange(Array(all.dropFirst(hidden)), isUser: { $0.role == .user })
        return ScrollViewReader { proxy in
            ScrollView {
                // A plain VStack, deliberately. `LazyVStack` estimates the height of every bubble
                // it has not built yet, and the estimates are wrong for text views: the scroll
                // thumb jumped as bubbles materialised, `scrollTo` landed short, and the reader
                // saw blank space while the lazy rows caught up. With the parsed text cached and
                // the window capped, laying every bubble out once is cheaper than that.
                VStack(alignment: .leading, spacing: 28) {
                    Color.clear
                        .frame(height: 1)
                        .id(Self.topAnchor)
                    if hidden > 0, readingOrder == .newestAtBottom {
                        earlierMessagesButton(hidden)
                    }
                    ForEach(shown, id: \.identifier) { message in
                        MessageBubble(
                            message: message,
                            mermaidAsCode: session.mermaidAsCode,
                            activity: session.activeActivity,
                            onPreview: { session.previewAttachment = $0 }
                        )
                        .id(message.identifier)
                    }
                    if hidden > 0, readingOrder == .newestAtTop {
                        earlierMessagesButton(hidden)
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
            .defaultScrollAnchor(readingOrder == .newestAtBottom ? .bottom : .top, for: .initialOffset)
            .onScrollGeometryChange(for: ChatScrollSnapshot.self) { geometry in
                ChatScrollSnapshot(
                    contentHeight: geometry.contentSize.height,
                    visibleMaxY: geometry.visibleRect.maxY
                )
            } action: { _, snapshot in
                guard readingOrder == .newestAtBottom else { return }
                if followBox.follow.apply(snapshot) {
                    scrollToLatest(proxy)
                }
            }
            // Geometry cannot separate a slow drag from streaming growth. While the reader is on
            // the scroll view, follow stands down; letting go at the bottom resumes it.
            .onScrollPhaseChange { _, phase in
                // `.animating` is Cue's own scrollTo, not the reader.
                let driving = phase == .tracking || phase == .interacting || phase == .decelerating
                if followBox.follow.setInteracting(driving), readingOrder == .newestAtBottom {
                    scrollToLatest(proxy)
                }
            }
            .onChange(of: all.count) { previous, next in
                if next > previous {
                    followBox.follow.jumpToLatest()
                }
                scrollToLatest(proxy)
            }
            .onChange(of: session.activeID) { _, _ in
                historyExpanded = false
                followBox.follow.jumpToLatest()
                scrollToLatest(proxy)
            }
            .onChange(of: readingOrder) { _, _ in
                followBox.follow.jumpToLatest()
                scrollToLatest(proxy)
            }
            .onAppear {
                followBox.follow.jumpToLatest()
                scrollToLatest(proxy)
            }
        }
    }

    private func earlierMessagesButton(_ count: Int) -> some View {
        Button {
            historyExpanded = true
        } label: {
            Label("Show \(count) earlier \(count == 1 ? "message" : "messages")", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cueGlass(cornerRadius: 14, interactive: true)
        .frame(maxWidth: .infinity)
    }

    /// Where a new turn lives: the bottom in chat order, the top in prompter order.
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard followBox.follow.shouldFollow else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            switch readingOrder {
            case .newestAtBottom: proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            case .newestAtTop: proxy.scrollTo(Self.topAnchor, anchor: .top)
            }
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
                            messageID: message.identifier,
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
