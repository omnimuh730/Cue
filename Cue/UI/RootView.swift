import SwiftUI

struct RootView: View {
    @Bindable var session: AppSession

    var body: some View {
        ZStack {
            CueWindowBackground()
            HStack(spacing: 0) {
                if session.sidebarOpen {
                    SidebarView(session: session)
                        .frame(width: CueTheme.sidebarWidth)
                        .cueGlass(cornerRadius: 18, interactive: true)
                        .padding(.leading, CueTheme.sidebarInset)
                        .padding(.top, CueTheme.headerHeight + CueTheme.sidebarInset)
                        .padding(.bottom, CueTheme.sidebarInset)
                        .padding(.trailing, 4)
                }
                VStack(spacing: 0) {
                    ChatView(session: session)
                        // Reserve the toolbar band; the bar itself is drawn window-wide below so
                        // scrolled content passes beneath the glass.
                        .safeAreaInset(edge: .top, spacing: 0) {
                            Color.clear.frame(height: CueTheme.headerHeight)
                        }
                    ComposerView(session: session)
                        .padding(.horizontal, CueTheme.composerInset)
                        .padding(.bottom, CueTheme.composerInset)
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
            if let notice = session.remoteNotice {
                Text(notice)
                    .font(.caption)
                    .padding(8)
                    .cueGlass(cornerRadius: 10)
                    .padding(.top, 48)
                    .onTapGesture { session.remoteNotice = nil }
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53, session.previewAttachment != nil {
                    session.previewAttachment = nil
                    return nil
                }
                if event.keyCode == 53, session.infoConversationID != nil {
                    session.infoConversationID = nil
                    return nil
                }
                if event.keyCode == 53, session.indexPrompt != nil {
                    session.skipProjectIndex()
                    return nil
                }
                if event.keyCode == 53, session.newProjectPromptOpen {
                    session.newProjectPromptOpen = false
                    return nil
                }
                if event.keyCode == 53, session.projectSettingsID != nil {
                    session.projectSettingsID = nil
                    return nil
                }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "n" {
                    session.newChat()
                    return nil
                }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "k" {
                    session.searchOpen = true
                    return nil
                }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
                    session.settingsOpen = true
                    return nil
                }
                return event
            }
        }
        .frame(minWidth: 420, minHeight: 420)
    }
}
