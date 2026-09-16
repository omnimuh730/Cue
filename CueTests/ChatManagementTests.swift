import Foundation
import SwiftData
import Testing
@testable import Cue

private struct Turn: Identifiable {
    var id: String
    var user: Bool
}

struct TurnTruncationTests {
    private let thread = [Turn(id: "u1", user: true), Turn(id: "a1", user: false), Turn(id: "u2", user: true), Turn(id: "a2", user: false)]

    @Test func regenerateKeepsThePromptAndDropsWhatFollowed() {
        let prompt = TurnTruncation.promptTurn(for: "a2", in: thread, key: \.id, isUser: \.user)
        #expect(prompt?.id == "u2")
        #expect(TurnTruncation.keep(thread, at: "u2", inclusive: true, key: \.id).map(\.id) == ["u1", "a1", "u2"])
    }

    @Test func aUserTurnIsItsOwnPrompt() {
        #expect(TurnTruncation.promptTurn(for: "u1", in: thread, key: \.id, isUser: \.user)?.id == "u1")
        #expect(TurnTruncation.keep(thread, at: "u1", inclusive: true, key: \.id).map(\.id) == ["u1"])
    }

    @Test func deleteFromDropsTheMessageItself() {
        #expect(TurnTruncation.keep(thread, at: "a1", inclusive: false, key: \.id).map(\.id) == ["u1"])
        #expect(TurnTruncation.keep(thread, at: "u1", inclusive: false, key: \.id).isEmpty)
    }

    @Test func unknownIDsChangeNothing() {
        #expect(TurnTruncation.keep(thread, at: "zz", inclusive: false, key: \.id).count == 4)
        #expect(TurnTruncation.promptTurn(for: "zz", in: thread, key: \.id, isUser: \.user) == nil)
        // A reply with no user turn before it (a repaired thread) has nothing to restart from.
        #expect(TurnTruncation.promptTurn(for: "a0", in: [Turn(id: "a0", user: false)], key: \.id, isUser: \.user) == nil)
    }

    @Test func truncationReanchorsThePreviousResponse() {
        // After cutting at u2, the continuation chains from a1, not the deleted a2.
        let turns = [
            ChatTurn(id: UUID(), role: .user, content: "q1", createdAt: .now, status: .complete, attachments: []),
            ChatTurn(id: UUID(), role: .assistant, content: "r1", createdAt: .now, status: .complete, attachments: [], responseID: "resp_1"),
            ChatTurn(id: UUID(), role: .user, content: "q2", createdAt: .now, status: .complete, attachments: [])
        ]
        let continuation = ChatContinuationBuilder.build(from: turns)
        #expect(continuation.previousResponseID == "resp_1")
        #expect(continuation.inputMessages?.map(\.content) == ["q2"])
    }
}

struct ConversationOrderTests {
    private struct Chat { var name: String; var pinnedAt: Date?; var updatedAt: Date }

    @Test func pinnedFirstNewestPinOnTopThenByActivity() {
        let now = Date()
        let chats = [
            Chat(name: "old", pinnedAt: nil, updatedAt: now.addingTimeInterval(-300)),
            Chat(name: "pin-early", pinnedAt: now.addingTimeInterval(-100), updatedAt: now.addingTimeInterval(-1000)),
            Chat(name: "new", pinnedAt: nil, updatedAt: now),
            Chat(name: "pin-late", pinnedAt: now.addingTimeInterval(-10), updatedAt: now.addingTimeInterval(-2000))
        ]
        let sorted = ConversationOrder.sorted(chats, pinnedAt: \.pinnedAt, updatedAt: \.updatedAt)
        #expect(sorted.map(\.name) == ["pin-late", "pin-early", "new", "old"])
    }
}

struct ConversationExportTests {
    @Test func markdownHasHeadingsAttachmentsAndSources() {
        let chip = ComposerTool.webSearch.attachment
        let file = MessageAttachment(kind: .text, mimeType: "text/plain", name: "notes.txt", text: "x", byteCount: 1)
        let turns = [
            ChatTurn(id: UUID(), role: .user, content: "  What's new?  ", createdAt: .now, status: .complete, attachments: [chip, file]),
            ChatTurn(id: UUID(), role: .assistant, content: "Lots.", createdAt: .now, status: .complete, attachments: [],
                     citations: [Citation(url: "https://a.com", title: "A", startIndex: nil, endIndex: nil)])
        ]
        let text = ConversationExport.markdown(title: "Today", turns: turns)
        #expect(text == """
        # Today

        ## User

        _Attached: notes.txt_

        What's new?

        ## Assistant

        Lots.

        Sources:
        1. [A](https://a.com)

        """)
    }

    @Test func fileNamesAreSafe() {
        #expect(ConversationExport.fileName(for: "a/b: c") == "a b  c.md")
        #expect(ConversationExport.fileName(for: "   ") == "Chat.md")
        #expect(ConversationExport.fileName(for: String(repeating: "x", count: 100)).count == 63)
    }
}

struct ChatSearchTests {
    private struct Chat { var id: String; var title: String; var messages: [Msg] }
    private struct Msg { var id: String; var text: String }

    private func hits(_ query: String, _ chats: [Chat]) -> [SearchHit<Chat, Msg>] {
        ChatSearch.hits(query: query, chats: chats, chatID: \.id, title: \.title, messages: \.messages, messageID: \.id, content: \.text)
    }

    private let chats = [
        Chat(id: "c1", title: "Swift actors", messages: [Msg(id: "m1", text: "Actors isolate state."), Msg(id: "m2", text: "Classes do not.")]),
        Chat(id: "c2", title: "Lunch", messages: [Msg(id: "m3", text: "An actor walks into a bar")])
    ]

    @Test func emptyQueryListsEveryChatOnce() {
        let all = hits("  ", chats)
        #expect(all.map(\.id) == ["c1", "c2"])
        #expect(all.allSatisfy { $0.message == nil })
    }

    @Test func titleHitsComeFirstThenMessagesInOrder() {
        let found = hits("actor", chats)
        #expect(found.map(\.id) == ["c1", "c1/m1", "c2/m3"])
        #expect(found[0].snippet == "Swift actors")
        #expect(found[1].snippet == "Actors isolate state.")
        #expect(found[2].message?.id == "m3")
        // The highlighted range points at the word, case-insensitively.
        let first = found[1]
        #expect(first.matchRange.map { String(first.snippet[$0]) } == "Actor")
    }

    @Test func snippetsAreCutAroundTheMatchWithEllipses() {
        let long = String(repeating: "a", count: 200) + " needle " + String(repeating: "b", count: 200)
        let range = long.range(of: "needle")!
        let excerpt = ChatSearch.snippet(of: long, around: range)
        #expect(excerpt.text.hasPrefix("…"))
        #expect(excerpt.text.hasSuffix("…"))
        #expect(excerpt.text.count == 1 + ChatSearch.snippetRadius + 6 + ChatSearch.snippetRadius + 1)
        #expect(excerpt.match.map { String(excerpt.text[$0]) } == "needle")
        // Near the edges nothing is cut.
        let short = "needle here\nsecond line"
        let edge = ChatSearch.snippet(of: short, around: short.range(of: "needle")!)
        #expect(edge.text == "needle here second line")
        #expect(edge.match.map { String(edge.text[$0]) } == "needle")
    }

    @Test func noMatchesMeansNoHits() {
        #expect(hits("zzz", chats).isEmpty)
    }
}

@MainActor
struct AppSessionChatManagementTests {
    private func makeSession() throws -> AppSession {
        let schema = Schema([Conversation.self, Message.self, Project.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return AppSession(container: container, settingsStore: SettingsStore())
    }

    private func seed(_ session: AppSession, title: String, turns: [(MessageRole, String)]) -> Conversation {
        let conversation = Conversation(title: title)
        session.container.mainContext.insert(conversation)
        for (offset, turn) in turns.enumerated() {
            let message = Message(role: turn.0, content: turn.1, createdAt: Date(timeIntervalSinceNow: Double(offset) - 100), status: .complete)
            message.conversation = conversation
            conversation.messages.append(message)
        }
        try? session.container.mainContext.save()
        session.reloadConversations()
        return conversation
    }

    @Test func deleteHidesAtOnceAndUndoBringsItBack() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Keep me", turns: [(.user, "hi")])
        _ = seed(session, title: "Other", turns: [])
        session.select(chat.identifier)
        session.deleteConversation(chat)
        #expect(!session.conversations.contains { $0.identifier == chat.identifier })
        #expect(session.activeID != chat.identifier)
        #expect(session.notice?.actionLabel == "Undo")
        session.performNoticeAction()
        #expect(session.conversations.contains { $0.identifier == chat.identifier })
        #expect(session.activeID == chat.identifier)
        #expect(session.notice == nil)
    }

    @Test func expiredDeletionsArePurgedOnReload() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Gone", turns: [])
        chat.deletedAt = Date(timeIntervalSinceNow: -(AppSession.undoWindow + 5))
        try session.container.mainContext.save()
        session.reloadConversations()
        let all = try session.container.mainContext.fetch(FetchDescriptor<Conversation>())
        #expect(!all.contains { $0.identifier == chat.identifier })
    }

    @Test func renameAndPin() throws {
        let session = try makeSession()
        let a = seed(session, title: "A", turns: [])
        let b = seed(session, title: "B", turns: [])
        session.renameConversation(a, to: "  Named  ")
        #expect(a.title == "Named")
        #expect(a.titleIsCustom == true)
        session.renameConversation(a, to: "   ")
        #expect(a.title == "Named")
        session.togglePin(a)
        #expect(session.conversations.first?.identifier == a.identifier)
        #expect(session.visibleConversations(pinned: true).map(\.identifier) == [a.identifier])
        #expect(session.visibleConversations(pinned: false).map(\.identifier) == [b.identifier])
        session.togglePin(a)
        #expect(a.pinnedAt == nil)
    }

    @Test func deleteFromMessageDropsItAndLaterTurnsAndResetsTheCodexThread() throws {
        let session = try makeSession()
        let chat = seed(session, title: "T", turns: [(.user, "q1"), (.assistant, "r1"), (.user, "q2"), (.assistant, "r2")])
        chat.codexThreadID = "thread"
        let ordered = chat.messages.sorted { $0.createdAt < $1.createdAt }
        session.deleteFromMessage(ordered[2].identifier)
        #expect(chat.messages.map(\.content).sorted() == ["q1", "r1"])
        #expect(chat.codexThreadID == nil)
        let remaining = try session.container.mainContext.fetch(FetchDescriptor<Message>())
        #expect(remaining.count == 2)
        #expect(session.isLatestReply(chat.messages.first { $0.content == "r1" }!))
    }

    @Test func adjacentSelectionWrapsThroughPinnedThenRecent() throws {
        let session = try makeSession()
        let a = seed(session, title: "A", turns: [])
        let b = seed(session, title: "B", turns: [])
        let c = seed(session, title: "C", turns: [])
        session.togglePin(c)
        // Order: C (pinned), then B, A by recency.
        session.select(c.identifier)
        session.selectAdjacentConversation(1)
        #expect(session.activeID == b.identifier)
        session.selectAdjacentConversation(1)
        #expect(session.activeID == a.identifier)
        session.selectAdjacentConversation(1)
        #expect(session.activeID == c.identifier)
        session.selectAdjacentConversation(-1)
        #expect(session.activeID == a.identifier)
    }

    @Test func escapeClosesOverlaysBeforeAnythingElse() throws {
        let session = try makeSession()
        _ = seed(session, title: "A", turns: [])
        #expect(session.dismissTopmost() == false)
        session.settingsOpen = true
        session.notify("hello")
        // The sheet the reader is looking at closes first; the toast goes on the next press.
        #expect(session.dismissTopmost())
        #expect(!session.settingsOpen)
        #expect(session.notice != nil)
        #expect(session.dismissTopmost())
        #expect(session.notice == nil)
        #expect(session.dismissTopmost() == false)
    }
}
