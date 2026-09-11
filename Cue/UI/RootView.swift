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
                        .cueGlass(cornerRadius: 0)
                }
                VStack(spacing: 0) {
                    HeaderView(session: session)
                    ChatView(session: session)
                    ComposerView(session: session)
                        .padding(.horizontal, CueTheme.composerInset)
                        .padding(.bottom, CueTheme.composerInset)
                }
            }
            if session.remote.cursor.active {
                VirtualCursorOverlay(state: session.remote.cursor)
            }
            if session.settingsOpen {
                SettingsView(session: session)
            }
            if session.searchOpen {
                SearchView(session: session)
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
