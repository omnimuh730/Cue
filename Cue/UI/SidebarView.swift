import SwiftUI

struct SidebarView: View {
    @Bindable var session: AppSession
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            navRow(title: "Search chats", symbol: "magnifyingglass") {
                session.searchOpen = true
            }
            navRow(title: "Load project", symbol: "folder") {
                session.openProjectFolder()
            }

            Text("Recents")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .allowsHitTesting(false)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(session.conversations, id: \.identifier) { conversation in
                        conversationRow(conversation)
                    }
                }
            }

            Spacer(minLength: 8)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            navRow(title: "Settings", symbol: "gear") {
                session.settingsOpen = true
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .padding(.top, 32)
        .background { CueWindowDragSource() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                session.sidebarOpen = false
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide sidebar")

            Text("Cue")
                .font(.system(size: 15, weight: .semibold))
                .allowsHitTesting(false)
            Spacer()
            Button {
                session.newChat()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New chat")
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private func navRow(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                        .fill(.primary.opacity(0.0001))
                )
        }
        .buttonStyle(SidebarRowButtonStyle())
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let isActive = session.activeID == conversation.identifier
        let isHovered = hoveredID == conversation.identifier
        let streaming = session.isStreaming(conversation)
        let unread = session.isUnread(conversation)
        let status = streaming ? (session.activity(for: conversation) ?? "Responding…") : nil
        let project = session.project(for: conversation)

        return HStack(spacing: 0) {
            Button {
                session.select(conversation.identifier)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(conversation.title)
                            .font(.system(size: 13, weight: isActive || unread ? .medium : .regular))
                            .lineLimit(1)
                        if let status {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .transition(.opacity)
                        } else if let project {
                            Text(project.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if streaming {
                        StreamingIndicator()
                    } else if unread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("New reply")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(minHeight: 34)
                .padding(.vertical, status == nil && project == nil ? 0 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(streaming ? "\(conversation.title), responding" : conversation.title)

            HStack(spacing: 0) {
                Button {
                    session.infoConversationID = conversation.identifier
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Thread info: cost, tokens, latency")
                .accessibilityLabel("Thread info")

                Button {
                    session.deleteConversation(conversation)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(streaming ? "Stop and delete" : "Delete chat")
            }
            .opacity(isHovered || isActive ? 0.9 : 0)
            .padding(.trailing, 2)
        }
        .background(
            RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                .fill(rowFill(isActive: isActive, isHovered: isHovered))
        )
        .animation(.easeInOut(duration: 0.18), value: streaming)
        .onHover { hovering in
            hoveredID = hovering ? conversation.identifier : (hoveredID == conversation.identifier ? nil : hoveredID)
        }
    }

    private func rowFill(isActive: Bool, isHovered: Bool) -> Color {
        if isActive { return Color.accentColor.opacity(0.22) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}

struct WorkspaceAvatar: View {
    var letter: String
    var isProject: Bool

    var body: some View {
        Text(letter)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isProject ? Color.white : Color.primary)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isProject ? Color.accentColor : Color.primary.opacity(0.1))
            )
            .accessibilityHidden(true)
    }
}

/// Three pulsing dots; the sidebar's "still working" tell for background chats.
struct StreamingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .frame(width: 24, height: 14)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                phase = (phase + 1) % 3
            }
        }
        .accessibilityLabel("Responding")
    }
}

private struct SidebarRowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                    .fill(configuration.isPressed || hovering ? Color.primary.opacity(0.06) : .clear)
            )
            .onHover { hovering = $0 }
    }
}
