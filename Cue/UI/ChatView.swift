import AppKit
import SwiftUI

struct ChatView: View {
    @Bindable var session: AppSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    let messages = session.activeMessages
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages, id: \.identifier) { message in
                        MessageBubble(
                            message: message,
                            mermaidAsCode: session.mermaidAsCode,
                            activity: session.activeActivity,
                            onPreview: { session.previewAttachment = $0 }
                        )
                        .id(message.identifier)
                    }
                }
                .frame(maxWidth: CueTheme.readingColumnMax)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CueTheme.Spacing.lg)
                .padding(.top, CueTheme.Spacing.md)
                .padding(.bottom, CueTheme.Spacing.lg)
            }
            .onChange(of: session.activeMessages.last?.content.count) { _, _ in
                if let id = session.activeMessages.last?.identifier {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onChange(of: session.activeID) { _, _ in
                if let id = session.activeMessages.last?.identifier {
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
                if project.codeFolder != nil {
                    Text("Cue will read **\(project.name)** with Codex and answer from that codebase.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(project.catalog == nil ? "Not indexed — Codex explores the tree on demand." : "Indexed \(project.catalogAt.map { $0.formatted(.relative(presentation: .named)) } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("New chat in **\(project.name)**.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(projectSummary(project))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    session.projectSettingsID = project.identifier
                } label: {
                    Label("Project settings", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .cueGlass(cornerRadius: 16, interactive: true)
                .padding(.top, CueTheme.Spacing.xs)
            } else {
                Text("Ask anything. Attach files, type / for a skill, or start a project.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button {
                        session.newProjectPromptOpen = true
                    } label: {
                        Label("New project", systemImage: "folder.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .cueGlass(cornerRadius: 16, interactive: true)
                    .help("Group chats with shared instructions and knowledge files")
                    Button {
                        session.openProjectFolder()
                    } label: {
                        Label("Open code folder", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .cueGlass(cornerRadius: 16, interactive: true)
                    .help("Chat about a local codebase through the Codex CLI")
                }
                .padding(.top, CueTheme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func projectSummary(_ project: Project) -> String {
        var parts: [String] = []
        if !(project.instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("custom instructions") }
        let files = project.knowledge.count
        if files > 0 { parts.append(files == 1 ? "1 knowledge file" : "\(files) knowledge files") }
        return parts.isEmpty ? "No instructions or knowledge yet — add them in project settings." : "Uses " + parts.joined(separator: " and ") + "."
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
                    Text(message.content)
                        .font(.system(size: 15, weight: .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    if status == .streaming, message.content.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
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
                        Text("▍")
                            .foregroundStyle(.secondary)
                    }
                    if let cost = message.costUsd, let timing = message.timing {
                        Text("\(Pricing.formatUsd(cost)) · \(Pricing.formatLatencyPair(timeToFirstTokenMs: timing.timeToFirstTokenMs, totalMs: timing.totalMs))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if role != .user { Spacer(minLength: 24) }
        }
    }
}
