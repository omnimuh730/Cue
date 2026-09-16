import Foundation
import Testing
@testable import Cue

struct MentionInvocationTests {
    @Test func queryOpensOnAWordStartingAtAnywhereInTheDraft() {
        #expect(MentionInvocation.query(in: "@") == "")
        #expect(MentionInvocation.query(in: "@web") == "web")
        #expect(MentionInvocation.query(in: "weather in Tokyo @web_se") == "web_se")
        #expect(MentionInvocation.query(in: "line one\n@w") == "w")
    }

    @Test func queryClosesOnWhitespaceEmailsAndMidWordAts() {
        #expect(MentionInvocation.query(in: "@web_search now") == nil)
        #expect(MentionInvocation.query(in: "mail robin@example.com") == nil)
        #expect(MentionInvocation.query(in: "no mention here") == nil)
        #expect(MentionInvocation.query(in: "") == nil)
    }

    @Test func removingTheQueryDropsTheTokenAndItsLeadingSpace() {
        #expect(MentionInvocation.removingQuery(from: "weather in Tokyo @web") == "weather in Tokyo")
        #expect(MentionInvocation.removingQuery(from: "@we") == "")
        #expect(MentionInvocation.removingQuery(from: "done @web_search already") == "done @web_search already")
    }

    @Test func filterMatchesNameLabelAndUnderscoreFreeTyping() {
        #expect(MentionInvocation.filter(ComposerTool.allCases, query: "") == ComposerTool.allCases)
        #expect(MentionInvocation.filter(ComposerTool.allCases, query: "web") == [.webSearch])
        #expect(MentionInvocation.filter(ComposerTool.allCases, query: "websea") == [.webSearch])
        #expect(MentionInvocation.filter(ComposerTool.allCases, query: "Web S") == [.webSearch])
        #expect(MentionInvocation.filter(ComposerTool.allCases, query: "zzz").isEmpty)
    }

    @Test func toolChipsAreFlagsNotPromptText() {
        let chip = ComposerTool.webSearch.attachment
        #expect(chip.kind == .tool)
        #expect(chip.name == "web_search")
        #expect(ComposerTool.webSearch.isRequested(in: [chip]))
        #expect(!ComposerTool.webSearch.isRequested(in: []))
        #expect(AttachmentPrompt.text(for: [chip], includePDFText: true) == nil)
        #expect(ProjectContext.knowledgeEntry(from: chip) == nil)
        let input = ResponsesClient().toResponseInput([ChatRequestMessage(role: .user, content: "hi", attachments: [chip])])
        let content = input.first?["content"] as? [[String: Any]]
        #expect(content?.count == 1)
        #expect(content?.first?["text"] as? String == "hi")
    }

    @Test func codexPromptAsksForSearchWhenMentioned() {
        let message = ChatRequestMessage(role: .user, content: "latest Swift version?", attachments: [])
        #expect(!CodexPrompt.build(messages: [message], catalog: nil).contains("web search"))
        let prompt = CodexPrompt.build(messages: [message], catalog: nil, webSearch: true)
        #expect(prompt.contains("Use web search"))
        #expect(prompt.hasSuffix("User question:\nlatest Swift version?"))
    }
}

struct CitationTests {
    private func run(_ events: [(String, [String: Any])]) -> [Citation] {
        let client = ResponsesClient()
        let state = ResponseStreamState()
        var found: [Citation] = []
        for (type, payload) in events {
            client.handle(type: type, payload: payload, settings: .default, state: state) { event in
                if case .citation(let citation) = event { found.append(citation) }
            }
        }
        return found
    }

    private func annotation(_ url: String, title: String = "T", start: Int = 0, end: Int = 5) -> [String: Any] {
        ["annotation": ["type": "url_citation", "url": url, "title": title, "start_index": start, "end_index": end]]
    }

    @Test func streamedAnnotationsBecomeCitationsOncePerURL() {
        let found = run([
            ("response.output_text.annotation.added", annotation("https://www.example.com/a", title: "Example A", start: 3, end: 9)),
            ("response.output_text.annotation.added", annotation("https://www.example.com/a", title: "Example A again")),
            ("response.output_text.annotation.added", ["annotation": ["type": "file_citation", "file_id": "f1"]]),
            ("response.output_text.annotation.added", annotation("https://b.org", title: ""))
        ])
        #expect(found.map(\.url) == ["https://www.example.com/a", "https://b.org"])
        #expect(found[0].title == "Example A")
        #expect(found[0].startIndex == 3)
        #expect(found[0].endIndex == 9)
        #expect(found[0].host == "example.com")
        #expect(found[1].displayTitle == "b.org")
    }

    @Test func completedResponseBackfillsWhatTheStreamMissed() {
        let completed: [String: Any] = [
            "response": [
                "id": "resp_1",
                "output": [
                    ["type": "web_search_call", "status": "completed"],
                    ["type": "message", "content": [
                        ["type": "output_text", "text": "…", "annotations": [
                            ["type": "url_citation", "url": "https://a.com", "title": "A"],
                            ["type": "url_citation", "url": "https://c.com", "title": "C"]
                        ]]
                    ]]
                ],
                "usage": ["input_tokens": 1, "output_tokens": 1]
            ]
        ]
        let found = run([
            ("response.output_text.annotation.added", annotation("https://a.com", title: "A")),
            ("response.completed", completed)
        ])
        #expect(found.map(\.url) == ["https://a.com", "https://c.com"])
    }

    @Test func messagesRoundTripCitations() {
        let message = Message(role: .assistant, content: "answer", status: .complete)
        #expect(message.citations.isEmpty)
        #expect(message.citationsJSON == nil)
        message.citations = [Citation(url: "https://a.com", title: "A", startIndex: nil, endIndex: nil)]
        #expect(message.asTurn().citations.map(\.url) == ["https://a.com"])
        var turn = message.asTurn()
        turn.citations = []
        message.apply(turn)
        #expect(message.citationsJSON == nil)
    }

    @Test func copyAppendsSources() {
        let citations = [Citation(url: "https://a.com/x", title: "A page", startIndex: nil, endIndex: nil)]
        #expect(MessageCopy.text(content: "Body.\n", citations: []) == "Body.\n")
        #expect(MessageCopy.text(content: "Body.\n", citations: citations) == "Body.\n\nSources:\n1. A page — https://a.com/x")
    }

    @Test func webSearchIsPerTurnOrGlobal() {
        var continuation = ChatContinuation(messages: [], previousResponseID: nil, inputMessages: nil)
        #expect(continuation.webSearch == false)
        continuation.webSearch = true
        #expect(continuation.webSearch)
        let instructions = SystemInstruction.buildResponseInstructions("", webSearchEnabled: true)
        #expect(instructions.contains("web search"))
    }
}
