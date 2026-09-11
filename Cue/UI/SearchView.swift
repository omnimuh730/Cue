import SwiftUI

struct SearchView: View {
    @Bindable var session: AppSession
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: CueTheme.Spacing.md) {
            TextField("Search chats", text: $query)
                .textFieldStyle(.roundedBorder)
            List(filtered, id: \.identifier) { conversation in
                Button(conversation.title) {
                    session.activeID = conversation.identifier
                    session.searchOpen = false
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 480, height: 360)
        .cueGlass(cornerRadius: 20)
    }

    private var filtered: [Conversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return session.conversations }
        return session.conversations.filter {
            $0.title.lowercased().contains(q) ||
            $0.messages.contains { $0.content.lowercased().contains(q) }
        }
    }
}
