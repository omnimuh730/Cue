import AppKit
import SwiftUI

/// ⌘K: find a chat by title or by anything said in it. Results show where the words were, arrow
/// keys move, Return opens (and jumps to the message).
struct SearchView: View {
    @Bindable var session: AppSession
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var allChats = false
    @FocusState private var fieldFocused: Bool

    private typealias Hit = SearchHit<Conversation, Message>

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
                    if session.selectedProject != nil {
                        Picker("Scope", selection: $allChats) {
                            Text(session.selectedProject?.name ?? "Project").tag(false)
                            Text("All chats").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 200)
                    }
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
                TextField("Search chats and messages", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .cueGlass(cornerRadius: 16, interactive: true)
                    .focused($fieldFocused)
                    .onSubmit { openSelected() }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                let hits = self.hits
                if hits.isEmpty {
                    Text(query.isEmpty ? "No chats yet." : "Nothing matches “\(query)”.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(hits.enumerated()), id: \.element.id) { item in
                                    row(item.element, selected: item.offset == selectedIndex)
                                        .id(item.element.id)
                                        .onHover { if $0 { selectedIndex = item.offset } }
                                }
                            }
                        }
                        .onChange(of: selectedIndex) { _, index in
                            guard hits.indices.contains(index) else { return }
                            proxy.scrollTo(hits[index].id)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 560, maxHeight: 460)
            .cueGlass(cornerRadius: 28, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
            .padding(24)
        }
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onChange(of: allChats) { _, _ in selectedIndex = 0 }
    }

    private var hits: [Hit] {
        let chats = allChats ? session.conversations : session.visibleConversations
        return ChatSearch.hits(
            query: query,
            chats: chats,
            chatID: { $0.identifier.uuidString },
            title: \.title,
            messages: { $0.messages.sorted { $0.createdAt < $1.createdAt } },
            messageID: { $0.identifier.uuidString },
            content: \.content
        )
    }

    private func move(_ delta: Int) {
        let count = hits.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func openSelected() {
        let hits = self.hits
        guard hits.indices.contains(selectedIndex) else { return }
        open(hits[selectedIndex])
    }

    private func open(_ hit: Hit) {
        session.select(hit.chat.identifier)
        session.scrollTarget = hit.message?.identifier
        session.searchOpen = false
    }

    private func row(_ hit: Hit, selected: Bool) -> some View {
        Button {
            open(hit)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.message == nil ? highlighted(hit.snippet.isEmpty ? hit.chat.title : hit.snippet, hit.matchRange) : AttributedString(hit.chat.title))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let project = session.project(for: hit.chat) {
                        Text(project.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    Text(hit.chat.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
                if let message = hit.message {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(message.role == .user ? "You" : "Cue")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(highlighted(hit.snippet, hit.matchRange))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func highlighted(_ text: String, _ range: Range<String.Index>?) -> AttributedString {
        var output = AttributedString(text)
        if let range, let lower = AttributedString.Index(range.lowerBound, within: output), let upper = AttributedString.Index(range.upperBound, within: output) {
            output[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            output[lower..<upper].foregroundColor = .primary
        }
        return output
    }
}
