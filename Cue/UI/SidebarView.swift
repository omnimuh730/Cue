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

            Text("Recents")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(session.conversations, id: \.identifier) { conversation in
                        conversationRow(conversation)
                    }
                }
            }

            Spacer(minLength: 8)

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

        return HStack(spacing: 0) {
            Button {
                session.activeID = conversation.identifier
            } label: {
                Text(conversation.title)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                session.deleteConversation(conversation)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isActive ? 0.85 : 0)
            .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                .fill(rowFill(isActive: isActive, isHovered: isHovered))
        )
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
