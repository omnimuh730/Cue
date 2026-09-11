import SwiftUI

/// Finder-style glass toolbar across the full top of the window. The sidebar starts below it,
/// the chat scrolls beneath it, it drags the window, and the sidebar toggle sits right after
/// the traffic lights.
struct ChatToolbar: View {
    @Bindable var session: AppSession

    var body: some View {
        HStack(spacing: 0) {
            Button {
                session.sidebarOpen.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(session.sidebarOpen ? "Hide sidebar" : "Show sidebar")
            .padding(.leading, CueTheme.trafficClearance)
            Spacer(minLength: 0)
        }
        .frame(height: CueTheme.headerHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .cueGlass(cornerRadius: 0, interactive: true)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .cueWindowDrag()
    }
}
