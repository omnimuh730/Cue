import SwiftUI

struct SidebarView: View {
    @Bindable var session: AppSession
    @State private var hoveredID: UUID?
    /// Chat whose title is being edited in place.
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            navRow(title: "Search chats", symbol: "magnifyingglass") {
                session.searchOpen = true
            }
            navRow(title: "New project", symbol: "folder.badge.plus") {
                session.newProjectPromptOpen = true
            }

            // The list fills the sidebar; empty space below the rows drags the window like the
            // header and footer do, so the whole sidebar is a grab handle.
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if !session.projects.isEmpty {
                            sectionTitle("Projects")
                            workspaceRow(nil)
                            ForEach(session.projects, id: \.identifier) { project in
                                workspaceRow(project)
                            }
                        }
                        let pinned = session.visibleConversations(pinned: true)
                        if !pinned.isEmpty {
                            sectionTitle("Pinned")
                            ForEach(pinned, id: \.identifier) { conversation in
                                conversationRow(conversation)
                            }
                        }
                        sectionTitle(session.selectedProject.map { "Chats in \($0.name)" } ?? "Recents")
                        ForEach(session.visibleConversations(pinned: false), id: \.identifier) { conversation in
                            conversationRow(conversation)
                        }
                        if session.visibleConversations.isEmpty {
                            Text("No chats yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                    .background { CueWindowDragSource() }
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
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
        .padding(.top, 8)
        .background { CueWindowDragSource() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Cue")
                .font(.system(size: 15, weight: .semibold))
                .allowsHitTesting(false)
            Spacer()
            Button {
                session.newChat()
                session.dismissSidebarIfOverlaid()
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .allowsHitTesting(false)
    }

    /// One workspace: nil is "All chats"; a project filters the list and hosts new chats.
    private func workspaceRow(_ project: Project?) -> some View {
        let id = project?.identifier
        let isActive = session.selectedProjectID == id
        let isHovered = hoveredID == (id ?? Self.allChatsHoverID)
        let streaming = project.map { p in session.conversations.contains { $0.projectID == p.identifier && session.isStreaming($0) } } ?? false

        return HStack(spacing: 0) {
            Button {
                session.selectWorkspace(id)
                session.dismissSidebarIfOverlaid()
            } label: {
                HStack(spacing: 8) {
                    if let project {
                        WorkspaceAvatar(letter: ProjectPaths.avatarLetter(project.name), isProject: true)
                    } else {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project?.name ?? "All chats")
                            .font(.system(size: 13, weight: isActive ? .medium : .regular))
                            .lineLimit(1)
                        if let project, let folder = project.codeFolder {
                            Label(ProjectPaths.displayPath(folder), systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                    if streaming {
                        CueMarkSpin(pointSize: 14, spinning: true, style: .busy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .padding(.trailing, 6)
                .frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(project?.name ?? "All chats")

            if let project {
                Button {
                    session.projectSettingsID = project.identifier
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Project settings: instructions, knowledge, code folder")
                .accessibilityLabel("Project settings")
                .opacity(isHovered || isActive ? 0.9 : 0)
                .padding(.trailing, 2)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                .fill(rowFill(isActive: isActive, isHovered: isHovered))
        )
        .onHover { hovering in
            let key = id ?? Self.allChatsHoverID
            hoveredID = hovering ? key : (hoveredID == key ? nil : hoveredID)
        }
    }

    private static let allChatsHoverID = UUID()

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
                session.dismissSidebarIfOverlaid()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        if renamingID == conversation.identifier {
                            TextField("Chat name", text: $renameText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .focused($renameFocused)
                                .onSubmit { commitRename(conversation) }
                                .onExitCommand { renamingID = nil }
                                .onChange(of: renameFocused) { _, focused in
                                    if !focused, renamingID == conversation.identifier { commitRename(conversation) }
                                }
                        } else {
                            Text(conversation.title)
                                .font(.system(size: 13, weight: isActive || unread ? .medium : .regular))
                                .lineLimit(1)
                        }
                        if let status {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .transition(.opacity)
                        } else if let project, session.selectedProjectID == nil {
                            Text(project.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if streaming {
                        CueMarkSpin(pointSize: 14, spinning: true, style: .busy)
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
                .padding(.vertical, status == nil && (project == nil || session.selectedProjectID != nil) ? 0 : 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(conversation) })
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
                .accessibilityLabel("Delete chat")
            }
            .opacity(isHovered || isActive ? 0.9 : 0)
            .padding(.trailing, 2)
        }
        .background(
            RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                .fill(rowFill(isActive: isActive, isHovered: isHovered))
        )
        .contextMenu { conversationMenu(conversation) }
        .animation(.easeInOut(duration: 0.18), value: streaming)
        .onHover { hovering in
            hoveredID = hovering ? conversation.identifier : (hoveredID == conversation.identifier ? nil : hoveredID)
        }
    }

    @ViewBuilder
    private func conversationMenu(_ conversation: Conversation) -> some View {
        Button("Rename…") { beginRename(conversation) }
        Button(conversation.pinnedAt == nil ? "Pin" : "Unpin") { session.togglePin(conversation) }
        Button("Thread info") { session.infoConversationID = conversation.identifier }
        Divider()
        Button("Copy as Markdown") {
            let text = ConversationExport.markdown(title: conversation.title, turns: conversation.messages.sorted { $0.createdAt < $1.createdAt }.map { $0.asTurn() })
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        Button("Save as Markdown…") { ConversationExport.save(conversation) }
        Divider()
        Button("Delete", role: .destructive) { session.deleteConversation(conversation) }
    }

    private func beginRename(_ conversation: Conversation) {
        renameText = conversation.title
        renamingID = conversation.identifier
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(_ conversation: Conversation) {
        guard renamingID == conversation.identifier else { return }
        renamingID = nil
        session.renameConversation(conversation, to: renameText)
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
