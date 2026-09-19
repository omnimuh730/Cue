import Foundation
import SwiftData
import Testing
@testable import Cue

private struct Branch {
    var id: String
    var parent: String?
}

struct ChatBranchingTests {
    private let tree = [
        Branch(id: "main", parent: nil),
        Branch(id: "a", parent: "main"),
        Branch(id: "b", parent: "a"),
        Branch(id: "other", parent: nil)
    ]

    private func parent(_ id: String) -> String? {
        tree.first { $0.id == id }?.parent
    }

    @Test func aBranchResolvesToTheChatItWasUltimatelyForkedFrom() {
        #expect(ChatBranching.rootID(of: "b", parent: parent) == "main")
        #expect(ChatBranching.rootID(of: "main", parent: parent) == "main")
        #expect(ChatBranching.rootID(of: "other", parent: parent) == "other")
    }

    @Test func aBrokenOrCyclicLinkStillResolves() {
        // A link to a chat that is gone stops the walk where it is.
        #expect(ChatBranching.rootID(of: "orphan", parent: { $0 == "orphan" ? "vanished" : nil }) == "vanished")
        // Two branches pointing at each other must not loop forever.
        let cycle = ["x": "y", "y": "x"]
        #expect(ChatBranching.rootID(of: "x", parent: { cycle[$0] }) == "y")
    }

    @Test func aFamilyIsMainFirstThenTheForksInTheOrderTheyWereMade() {
        let family = ChatBranching.family(of: "b", in: tree, key: \.id, parent: \.parent)
        #expect(family.map(\.id) == ["main", "a", "b"])
        // Any member of the family answers with the same tabs.
        #expect(ChatBranching.family(of: "main", in: tree, key: \.id, parent: \.parent).map(\.id) == ["main", "a", "b"])
        #expect(ChatBranching.family(of: "other", in: tree, key: \.id, parent: \.parent).map(\.id) == ["other"])
    }

    @Test func childrenAreTheBranchesForkedDirectlyFromAChat() {
        #expect(ChatBranching.children(of: "main", in: tree, parent: \.parent).map(\.id) == ["a"])
        #expect(ChatBranching.children(of: "a", in: tree, parent: \.parent).map(\.id) == ["b"])
        #expect(ChatBranching.children(of: "b", in: tree, parent: \.parent).isEmpty)
    }

    @Test func defaultNamesReadLikeBranchNames() {
        #expect(ChatBranching.defaultName(index: 0) == "main")
        #expect(ChatBranching.defaultName(index: 1) == "fork 1")
        #expect(ChatBranching.defaultName(index: 3) == "fork 3")
    }

    @Test func quotingKeepsTheWholePassageInOneBlock() {
        let quoted = ChatBranching.quote("  first line\n\nsecond line  ")
        #expect(quoted == "> first line\n>\n> second line")
        #expect(ChatBranching.quote("   ").isEmpty)
    }

    @Test func anOverLongPassageIsCut() {
        let long = String(repeating: "x", count: ChatBranching.maxQuoteCharacters + 50)
        let quoted = ChatBranching.quote(long)
        #expect(quoted.hasSuffix("…"))
        #expect(quoted.count == ChatBranching.maxQuoteCharacters + 3) // "> " + text + "…"
    }

    @Test func aQuoteLandsUnderWhatWasAlreadyTyped() {
        #expect(ChatBranching.appendingQuote("hi", to: "") == "> hi\n\n")
        #expect(ChatBranching.appendingQuote("hi", to: " what about\n") == "what about\n\n> hi\n\n")
        #expect(ChatBranching.appendingQuote("  ", to: "kept") == "kept")
    }
}

@MainActor
struct AppSessionBranchTests {
    private func makeSession() throws -> AppSession {
        let schema = Schema([Conversation.self, Message.self, Project.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return AppSession(container: container, settingsStore: SettingsStore())
    }

    @discardableResult
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

    private func ordered(_ conversation: Conversation) -> [Message] {
        conversation.messages.sorted { $0.createdAt < $1.createdAt }
    }

    @Test func forkingCopiesTheThreadUpToTheMessageAndLeavesTheOriginalAlone() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "r1"), (.user, "q2"), (.assistant, "r2")])
        chat.codexThreadID = "thread"
        let cut = ordered(chat)[1]

        let branch = try #require(session.fork(from: cut.identifier))
        #expect(ordered(branch).map(\.content) == ["q1", "r1"])
        // The chat it came from keeps every turn, and its Codex thread.
        #expect(ordered(chat).map(\.content) == ["q1", "r1", "q2", "r2"])
        #expect(chat.codexThreadID == "thread")
        // The copies are rows of their own; editing the branch cannot touch the original.
        #expect(Set(ordered(branch).map(\.identifier)).isDisjoint(with: Set(ordered(chat).map(\.identifier))))
        #expect(branch.codexThreadID == nil)
        #expect(branch.forkedFromID == chat.identifier)
        #expect(branch.forkedAtMessageID == cut.identifier)
        // The fork opens as the chat on screen.
        #expect(session.activeID == branch.identifier)
    }

    @Test func bothVersionsShowAsTabsOnOneSidebarRow() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "r1")])
        #expect(session.showsBranchTabs == false)

        let branch = try #require(session.fork(from: ordered(chat)[1].identifier))
        #expect(session.showsBranchTabs)
        #expect(session.branchTabs.map(\.identifier) == [chat.identifier, branch.identifier])
        #expect(session.branchName(chat) == "main")
        #expect(session.branchName(branch) == "fork 1")
        // One row in the sidebar, not two.
        #expect(session.sidebarConversations(pinned: false).map(\.identifier) == [chat.identifier])
        #expect(session.branchCount(of: branch) == 2)

        session.renameBranch(branch, to: "  without the detour  ")
        #expect(session.branchName(branch) == "without the detour")
    }

    @Test func aSidebarRowReopensOnTheBranchItWasLeftOn() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "r1")])
        let other = seed(session, title: "Other", turns: [(.user, "q")])
        let branch = try #require(session.fork(from: ordered(chat)[1].identifier))

        session.select(other.identifier)
        session.selectFamily(chat.identifier)
        #expect(session.activeID == branch.identifier)

        session.select(chat.identifier)
        session.select(other.identifier)
        session.selectFamily(chat.identifier)
        #expect(session.activeID == chat.identifier)
    }

    @Test func deletingABranchKeepsWhatWasForkedFromItAndUndoPutsItBack() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "r1")])
        let first = try #require(session.fork(from: ordered(chat)[1].identifier))
        let second = try #require(session.fork(from: ordered(first)[1].identifier))
        #expect(second.forkedFromID == first.identifier)

        session.deleteBranch(first)
        #expect(!session.conversations.contains { $0.identifier == first.identifier })
        // The branch forked from it survives, reattached where its parent was.
        #expect(second.forkedFromID == chat.identifier)
        #expect(session.branchTabs.map(\.identifier) == [chat.identifier, second.identifier])
        // Closing a tab the reader is not on leaves them where they were.
        #expect(session.activeID == second.identifier)

        session.performNoticeAction()
        #expect(session.conversations.contains { $0.identifier == first.identifier })
        #expect(second.forkedFromID == first.identifier)
    }

    @Test func closingTheTabOnScreenLandsOnItsParent() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "r1")])
        let branch = try #require(session.fork(from: ordered(chat)[1].identifier))
        #expect(session.activeID == branch.identifier)
        session.deleteBranch(branch)
        #expect(session.activeID == chat.identifier)
        #expect(session.showsBranchTabs == false)
    }

    @Test func deletingTheChatTakesItsBranchesWithItAndUndoBringsThemBack() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "r1")])
        let branch = try #require(session.fork(from: ordered(chat)[1].identifier))

        session.deleteConversation(branch)
        #expect(!session.conversations.contains { $0.identifier == chat.identifier })
        #expect(!session.conversations.contains { $0.identifier == branch.identifier })

        session.performNoticeAction()
        #expect(session.conversations.contains { $0.identifier == chat.identifier })
        #expect(session.conversations.contains { $0.identifier == branch.identifier })
    }

    @Test func selectedTextCanBeQuotedOrForkedFrom() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "the answer is 42")])
        let reply = ordered(chat)[1]
        session.select(chat.identifier)

        session.selectText("the answer is 42", messageID: reply.identifier, at: CGRect(x: 10, y: 20, width: 100, height: 18))
        #expect(session.textSelection?.messageID == reply.identifier)
        session.draft = "why"
        session.addSelectionToDraft()
        #expect(session.draft == "why\n\n> the answer is 42\n\n")
        #expect(session.textSelection == nil)

        session.draft = ""
        session.selectText("the answer is 42", messageID: reply.identifier, at: .zero)
        session.forkFromSelection()
        let branch = try #require(session.activeConversation)
        #expect(branch.forkedFromID == chat.identifier)
        #expect(session.draft == "> the answer is 42\n\n")
        // Selecting nothing closes the actions instead of opening them on an empty passage.
        session.selectText("   ", messageID: reply.identifier, at: .zero)
        #expect(session.textSelection == nil)
    }

    @Test func escapeClosesTheSelectionActionsFirst() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1")])
        session.select(chat.identifier)
        session.selectText("q1", messageID: ordered(chat)[0].identifier, at: .zero)
        session.settingsOpen = true
        #expect(session.dismissTopmost())
        #expect(session.textSelection == nil)
        #expect(session.settingsOpen)
    }

    @Test func branchesStepWithTheirOwnShortcutAndThreadsWithTheSidebarOrder() throws {
        let session = try makeSession()
        let chat = seed(session, title: "Roots", turns: [(.user, "q1"), (.assistant, "r1")])
        let other = seed(session, title: "Other", turns: [(.user, "q")])
        let branch = try #require(session.fork(from: ordered(chat)[1].identifier))

        session.select(chat.identifier)
        session.selectAdjacentBranch(1)
        #expect(session.activeID == branch.identifier)
        session.selectAdjacentBranch(1)
        #expect(session.activeID == chat.identifier)

        // ⌘] moves to the next thread, not the next branch.
        session.selectAdjacentConversation(1)
        #expect(session.activeID == other.identifier)
        session.selectAdjacentConversation(1)
        let active = try #require(session.activeConversation)
        #expect(session.rootConversation(of: active).identifier == chat.identifier)
    }
}
