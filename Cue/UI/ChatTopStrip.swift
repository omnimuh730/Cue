import SwiftUI

/// Replaces the old title bar: a thin drag handle across the top of the reading column and,
/// only while the sidebar is hidden, a button to bring it back. Thread details live in the
/// sidebar row's info button instead.
struct ChatTopStrip: View {
    @Bindable var session: AppSession

    var body: some View {
        HStack(spacing: 0) {
            if !session.sidebarOpen {
                Button {
                    session.sidebarOpen = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show sidebar")
                .padding(.leading, CueTheme.trafficClearance)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .cueWindowDrag()
    }
}
