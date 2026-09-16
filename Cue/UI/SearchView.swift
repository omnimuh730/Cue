import SwiftUI

struct SearchView: View {
    @Bindable var session: AppSession
    @State private var query = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { session.searchOpen = false }

            VStack(alignment: .leading, spacing: CueTheme.Spacing.md) {
                HStack {
                    Text("Search")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button {
                        session.searchOpen = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .cueGlass(cornerRadius: 14, interactive: true)
                }
                TextField("Search chats", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .cueGlass(cornerRadius: 16, interactive: true)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered, id: \.identifier) { conversation in
                            Button {
                                session.select(conversation.identifier)
                                session.searchOpen = false
                            } label: {
                                Text(conversation.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .cueGlass(cornerRadius: 12, interactive: true)
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 520, height: 400)
            .cueGlass(cornerRadius: 28, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        }
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
