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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                            canRegenerate: message.role == .assistant && session.isLatestReply(message),
                            onPreview: { session.previewAttachment = $0 },
                            onRegenerate: { session.regenerate(messageID: message.identifier, model: $0) },
                            onEdit: { session.resend(userMessageID: message.identifier, text: $0) },
                            onDeleteFrom: { session.deleteFromMessage(message.identifier) }
                        )
                        .id(message.identifier)
                        // A new turn settles in from the edge it arrives at; a removed one just fades.
                        .transition(.asymmetric(
                            insertion: .move(edge: readingOrder == .newestAtBottom ? .bottom : .top).combined(with: .opacity),
                            removal: .opacity
                        ))
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
                // Only a turn arriving or leaving animates; streaming growth and resizes stay direct.
                .animation(reduceMotion ? nil : CueMotion.arrive, value: all.count)
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
                jumpToTarget(proxy)
            }
            .onChange(of: session.scrollTarget) { _, _ in
                jumpToTarget(proxy)
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
        .buttonStyle(CuePressButtonStyle())
        .cueGlass(cornerRadius: 14, interactive: true)
        .cueHoverLift(1.04)
        .frame(maxWidth: .infinity)
    }

    /// Lands on the message a search hit pointed at, once, and unpins follow so streaming
    /// growth does not pull the reader away from it (the geometry re-pins if it is the bottom).
    private func jumpToTarget(_ proxy: ScrollViewProxy) {
        guard let target = session.scrollTarget else { return }
        session.scrollTarget = nil
        if !historyExpanded, session.activeMessages.count > Self.historyWindow,
           session.activeMessages.prefix(session.activeMessages.count - Self.historyWindow).contains(where: { $0.identifier == target }) {
            historyExpanded = true
        }
        followBox.follow.pinnedToBottom = false
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
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
    /// Only the newest reply can be answered again in place.
    var canRegenerate = false
    var onPreview: (MessageAttachment) -> Void
    var onRegenerate: (ModelID?) -> Void = { _ in }
    var onEdit: (String) -> Void = { _ in }
    var onDeleteFrom: () -> Void = {}

    @State private var hovering = false
    @State private var copied = false
    @State private var editing = false
    @State private var editText = ""

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
                    if editing {
                        editor
                    } else {
                        SelectableTextView(text: MarkdownTextBuilder.plain(message.content))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        actionRow
                    }
                } else {
                    if status == .streaming, message.content.isEmpty {
                        HStack(spacing: 8) {
                            CueOrb(size: 18, energy: 1)
                            Text(activity ?? "Thinking…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                                // A light sweep says "working" without a second spinner.
                                .cueShimmer(active: true, period: 1.9, strength: 0.55)
                        }
                        .padding(.vertical, 4)
                        .animation(.easeInOut(duration: 0.18), value: activity)
                    } else if status == .error {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Label(message.content, systemImage: "exclamationmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                            // A failed turn is the one place the action stays visible: the
                            // reader needs it now, not after finding the hover row.
                            Button {
                                onRegenerate(nil)
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(CuePressButtonStyle())
                            .cueGlass(cornerRadius: 13, interactive: true)
                            .cueHoverLift(1.04)
                            .help("Send the question again")
                        }
                    } else {
                        MarkdownMessageView(
                            messageID: message.identifier,
                            text: message.content,
                            mermaidAsCode: mermaidAsCode,
                            streaming: status == .streaming
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !message.citations.isEmpty {
                        CitationRow(citations: message.citations)
                            .padding(.top, 2)
                    }
                    if status == .streaming, !message.content.isEmpty {
                        CueOrb(size: 14, energy: 1)
                    }
                    if status != .streaming {
                        HStack(spacing: 10) {
                            if let cost = message.costUsd, let timing = message.timing {
                                Text("\(Pricing.formatUsd(cost)) · \(Pricing.formatLatencyPair(timeToFirstTokenMs: timing.timeToFirstTokenMs, totalMs: timing.totalMs))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            actionRow
                        }
                    }
                }
            }
            if role != .user { Spacer(minLength: 24) }
        }
        .background { HoverRegion { hovering = $0 } }
    }

    /// Copy, then the actions that fit the role, then the time. Revealed on hover so the
    /// reading column stays quiet; the row is one line and never taller than 22pt.
    private var actionRow: some View {
        HStack(spacing: 2) {
            actionButton(copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc", tint: copied ? .green : .secondary, help: "Copy message text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(MessageCopy.text(content: message.content, citations: message.citations), forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    copied = false
                }
            }
            if role == .assistant, canRegenerate, status != .error {
                regenerateMenu
            }
            if role == .user {
                actionButton("Edit", symbol: "pencil", help: "Edit and send again; later turns are removed") {
                    editText = message.content
                    editing = true
                }
            }
            actionButton("Delete", symbol: "trash", help: role == .user ? "Delete this message and everything after it" : "Delete this reply and everything after it") {
                onDeleteFrom()
            }
            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, 6)
                .help(message.createdAt.formatted(date: .abbreviated, time: .standard))
        }
        .opacity(hovering || copied ? 1 : 0)
        .offset(y: hovering || copied ? 0 : 3)
        .animation(CueMotion.control, value: hovering || copied)
    }

    private var regenerateMenu: some View {
        Menu {
            Button("Regenerate") { onRegenerate(nil) }
            Divider()
            ForEach(ModelCatalog.models) { model in
                Button(model.label) { onRegenerate(model.id) }
            }
        } label: {
            Label("Regenerate", systemImage: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .contentShape(Capsule())
        } primaryAction: {
            onRegenerate(nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        .background(Color.primary.opacity(hovering ? 0.06 : 0), in: Capsule())
        .help("Answer again; the menu picks another model")
        .accessibilityLabel("Regenerate")
    }

    private func actionButton(_ title: String, symbol: String, tint: Color = .secondary, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(hovering ? 0.06 : 0), in: Capsule())
        .help(help)
        .accessibilityLabel(title)
    }

    /// In-place editor for a user turn. Save sends it again (⌘⏎); Cancel (esc) keeps the original.
    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $editText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 240)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
            HStack(spacing: 8) {
                Button("Cancel") { editing = false }
                    .keyboardShortcut(.cancelAction)
                Button("Send") {
                    editing = false
                    onEdit(editText)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.attachments.isEmpty)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// What the copy button puts on the pasteboard: the answer, then its sources if it had any.
nonisolated enum MessageCopy {
    static func text(content: String, citations: [Citation]) -> String {
        guard !citations.isEmpty else { return content }
        let sources = citations.enumerated().map { index, citation in
            "\(index + 1). \(citation.displayTitle) — \(citation.url)"
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\nSources:\n" + sources.joined(separator: "\n")
    }
}
