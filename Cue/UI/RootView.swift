import SwiftUI

struct RootView: View {
    @Bindable var session: AppSession
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            CueWindowBackground()
            GeometryReader { geo in
                // Below the split width the sidebar floats over the chat; side by side it would
                // leave a transcript column narrower than a single line of prose.
                let overlaid = geo.size.width < CueTheme.sidebarSplitMinWidth
                HStack(spacing: 0) {
                    if session.sidebarOpen, !overlaid {
                        sidebar
                    }
                    VStack(spacing: 0) {
                        ChatView(session: session)
                            // Reserve the toolbar band; the bar itself is drawn window-wide below
                            // so scrolled content passes beneath the glass. Branch tabs sit in
                            // the same inset, under the toolbar and above the transcript.
                            .safeAreaInset(edge: .top, spacing: 0) {
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: CueTheme.headerHeight)
                                    if session.showsBranchTabs {
                                        BranchTabBar(session: session)
                                    }
                                }
                            }
                            .environment(\.expandDiagram) { session.previewDiagram = $0 }
                        ComposerView(session: session)
                            .padding(.horizontal, CueTheme.composerInset)
                            .padding(.bottom, CueTheme.composerInset)
                    }
                }
                .overlay(alignment: .leading) {
                    if session.sidebarOpen, overlaid {
                        floatingSidebar(width: geo.size.width)
                    }
                }
                .onChange(of: overlaid, initial: true) { _, isOverlaid in
                    session.setSidebarOverlaid(isOverlaid)
                }
            }
            // The whole window takes a drop, not just the composer's text strip.
            .onDrop(of: DroppedItems.acceptedTypes, isTargeted: $dropTargeted) { providers in
                session.acceptDrop(providers)
                return true
            }
            .overlay {
                if dropTargeted {
                    DropTargetOverlay()
                }
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                ChatToolbar(session: session)
                    .ignoresSafeArea(edges: .top)
            }
            if session.settingsOpen {
                SettingsView(session: session)
            }
            if session.searchOpen {
                SearchView(session: session)
            }
            if let preview = session.previewAttachment {
                AttachmentPreviewOverlay(attachment: preview) {
                    session.previewAttachment = nil
                }
            }
            if let selection = session.textSelection {
                SelectionActionsOverlay(
                    selection: selection,
                    onAddToChat: { session.addSelectionToDraft() },
                    onFork: { session.forkFromSelection() }
                )
            }
            if let diagram = session.previewDiagram {
                MermaidPreviewOverlay(source: diagram) {
                    session.previewDiagram = nil
                }
            }
            if let infoID = session.infoConversationID,
               let conversation = session.conversations.first(where: { $0.identifier == infoID }) {
                ThreadInfoView(conversation: conversation, project: session.project(for: conversation)) {
                    session.infoConversationID = nil
                }
            }
            if let settingsID = session.projectSettingsID,
               let project = session.projects.first(where: { $0.identifier == settingsID }) {
                ProjectSettingsView(session: session, project: project) {
                    session.projectSettingsID = nil
                }
            }
            if session.newProjectPromptOpen {
                NewProjectDialog(
                    onCreate: { name in
                        session.newProjectPromptOpen = false
                        session.createProject(name: name)
                    },
                    onCancel: { session.newProjectPromptOpen = false }
                )
            }
            if let project = session.indexPrompt {
                IndexProjectDialog(
                    project: project,
                    indexing: session.indexing,
                    error: session.indexError,
                    onIndex: { session.confirmProjectIndex() },
                    onSkip: { session.skipProjectIndex() }
                )
            }
        }
        .overlay {
            // Cursor coordinates are panel content space; the overlay must span the full window,
            // including the transparent title bar the ZStack above is inset from.
            if session.remote.cursor.active {
                VirtualCursorOverlay(state: session.remote.cursor)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            if let notice = session.notice {
                NoticeBanner(
                    notice: notice,
                    onAction: { session.performNoticeAction() },
                    onDismiss: { session.dismissNotice() }
                )
                .padding(.top, 48)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    // Overlays that own their own Escape (the search field, an editor) still see
                    // it; anything else closes the topmost surface or stops the live reply.
                    if session.searchOpen { return event }
                    return session.dismissTopmost() ? nil : event
                }
                guard event.modifierFlags.contains(.command) else { return event }
                switch event.charactersIgnoringModifiers {
                case "n":
                    session.newChat()
                    return nil
                case "k":
                    session.searchOpen = true
                    return nil
                case ",":
                    session.settingsOpen = true
                    return nil
                case "]":
                    // ⌥⌘] steps through the branches of this chat; ⌘] through the sidebar.
                    if event.modifierFlags.contains(.option) {
                        session.selectAdjacentBranch(1)
                    } else {
                        session.selectAdjacentConversation(1)
                    }
                    return nil
                case "[":
                    if event.modifierFlags.contains(.option) {
                        session.selectAdjacentBranch(-1)
                    } else {
                        session.selectAdjacentConversation(-1)
                    }
                    return nil
                default:
                    return event
                }
            }
        }
        .frame(minWidth: 420, minHeight: 420)
    }

    private var sidebar: some View {
        SidebarView(session: session)
            .frame(width: CueTheme.sidebarWidth)
            .cueGlass(cornerRadius: 18, interactive: true)
            .padding(.leading, CueTheme.sidebarInset)
            .padding(.top, CueTheme.headerHeight + CueTheme.sidebarInset)
            .padding(.bottom, CueTheme.sidebarInset)
            .padding(.trailing, 4)
    }

    /// The same sidebar, laid over the chat with a scrim, for windows too narrow to split.
    private func floatingSidebar(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { session.sidebarOpen = false }
            SidebarView(session: session)
                .frame(width: min(CueTheme.sidebarWidth, max(200, width - CueTheme.sidebarOverlayGutter)))
                .cueGlass(cornerRadius: 18, interactive: true)
                .padding(.leading, CueTheme.sidebarInset)
                .padding(.top, CueTheme.headerHeight + CueTheme.sidebarInset)
                .padding(.bottom, CueTheme.sidebarInset)
                .shadow(color: .black.opacity(0.3), radius: 24, x: 6)
        }
    }
}

/// Shown while a drag hovers over the window so it is obvious the drop will be taken.
private struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            Label("Drop to attach", systemImage: "paperclip")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .cueGlass(cornerRadius: 16, interactive: false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(CueTheme.sidebarInset)
        }
        .allowsHitTesting(false)
    }
}

/// The one transient message Cue shows: an error, a confirmation, or an "Undo".
private struct NoticeBanner: View {
    var notice: Notice
    var onAction: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(notice.text)
                .font(.system(size: 12))
                .lineLimit(2)
            if let label = notice.actionLabel {
                Button(action: onAction) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("z", modifiers: .command)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .cueGlass(cornerRadius: 14, interactive: true)
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .onTapGesture(perform: onDismiss)
    }
}
