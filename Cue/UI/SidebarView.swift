import SwiftUI

struct SidebarView: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: CueTheme.Spacing.sm) {
            HStack(spacing: CueTheme.Spacing.xs) {
                CueMark(pointSize: 14)
                Text("Cue")
                    .font(.headline)
                Spacer()
                Button {
                    session.newChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("New chat")
            }
            .padding(.horizontal, CueTheme.Spacing.md)
            .padding(.top, 36)

            Button {
                session.searchOpen = true
            } label: {
                Label("Search chats", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, CueTheme.Spacing.md)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(session.conversations, id: \.identifier) { conversation in
                        HStack {
                            Button {
                                session.activeID = conversation.identifier
                            } label: {
                                Text(conversation.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Button {
                                session.deleteConversation(conversation)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(0.6)
                        }
                        .padding(.horizontal, CueTheme.Spacing.sm)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                                .fill(session.activeID == conversation.identifier ? Color.primary.opacity(0.08) : .clear)
                        )
                    }
                }
                .padding(.horizontal, CueTheme.Spacing.xs)
            }
            Spacer()
            Button("Settings") { session.settingsOpen = true }
                .buttonStyle(.plain)
                .padding(CueTheme.Spacing.md)
        }
    }
}
