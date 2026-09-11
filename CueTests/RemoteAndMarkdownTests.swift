import CoreGraphics
import Foundation
import Testing
@testable import Cue

struct RemoteAndMarkdownTests {
    @Test func cursorDeltaClampsAndTracksDirection() {
        // +dy moves down in content space, matching Quartz deltas and SwiftUI's origin.
        let moved = RemoteCursorMath.applyDelta(virtualX: 100, virtualY: 100, dx: 10, dy: 5, width: 800, height: 600)
        #expect(moved.virtualX == 110)
        #expect(moved.virtualY == 105)
        #expect(moved.moved)

        let clamped = RemoteCursorMath.applyDelta(virtualX: 798, virtualY: 1, dx: 50, dy: -50, width: 800, height: 600)
        #expect(clamped.virtualX == 799)
        #expect(clamped.virtualY == 0)
        #expect(clamped.moved)

        let stuck = RemoteCursorMath.applyDelta(virtualX: 799, virtualY: 0, dx: 5, dy: -5, width: 800, height: 600)
        #expect(!stuck.moved)

        let jump = RemoteCursorMath.applyDelta(virtualX: 10, virtualY: 10, dx: 5000, dy: 0, width: 800, height: 600)
        #expect(!jump.moved)
        #expect(jump.virtualX == 10)
    }

    @Test func remoteTextEditsApplyToDraft() {
        var draft = "hello world"
        RemoteTextEdit.apply(RemoteTextEdit.deleteBackward, to: &draft)
        #expect(draft == "hello worl")
        RemoteTextEdit.apply(RemoteTextEdit.deleteWord, to: &draft)
        #expect(draft == "hello ")
        RemoteTextEdit.apply(RemoteTextEdit.deleteWord, to: &draft)
        #expect(draft == "")
        RemoteTextEdit.apply(RemoteTextEdit.deleteBackward, to: &draft)
        #expect(draft == "")
        RemoteTextEdit.apply("a", to: &draft)
        RemoteTextEdit.apply("\n", to: &draft)
        #expect(draft == "a\n")
    }

    @Test func keyCodesRoundTrip() {
        #expect(KeyCodes.code(for: 0x04) == "KeyH")
        #expect(KeyCodes.keyCode(for: "KeyH") == 0x04)
        #expect(KeyCodes.code(for: 0x56) == "Numpad4")
        #expect(KeyCodes.keyCode(for: "Numpad4") == 0x56)
        #expect(KeyCodes.code(for: 0x7E) == "ArrowUp")
        #expect(KeyCodes.code(for: 0xFF) == "Unidentified")
        // Both Return and keypad Enter map to Enter; the reverse map picks the main Return key.
        #expect(KeyCodes.code(for: 0x4C) == "Enter")
        #expect(KeyCodes.keyCode(for: "Enter") == 0x24)
        #expect(KeyCodes.key(for: "KeyA") == "a")
        #expect(KeyCodes.key(for: "Digit1") == "Digit1")
    }

    @Test func remoteHotkeysMatchWithSharedKeyTable() throws {
        let pattern = try #require(AcceleratorMatch.parseElectronAccelerator("CommandOrControl+num4"))
        let code = KeyCodes.code(for: 0x56)
        let payload = KeyPayload(code: code, key: KeyCodes.key(for: code), altKey: false, ctrlKey: false, metaKey: true, shiftKey: false)
        #expect(AcceleratorMatch.payloadMatches(payload, pattern: pattern))
        #expect(CarbonHotkey.from(pattern)?.keyCode == 0x56)
    }

    @Test func markdownSplitsFencesHeadingsAndParagraphs() {
        let text = """
        Here's a design:

        ```mermaid
        flowchart TD
          A --> B
        ```

        ### Typical trip flow
        1. Rider opens app
        2. Match

        ```swift
        let x = 1
        ```
        Trailing text
        """
        let blocks = MarkdownBlocks.split(text)
        #expect(blocks.count == 6)
        #expect(blocks[0] == .paragraph("Here's a design:"))
        #expect(blocks[1] == .mermaid("flowchart TD\n  A --> B"))
        #expect(blocks[2] == .heading(level: 3, "Typical trip flow"))
        #expect(blocks[3] == .paragraph("1. Rider opens app\n2. Match"))
        #expect(blocks[4] == .code(language: "swift", "let x = 1"))
        #expect(blocks[5] == .paragraph("Trailing text"))
    }

    @Test func markdownKeepsUnterminatedFenceWhileStreaming() {
        let blocks = MarkdownBlocks.split("Intro\n```mermaid\nflowchart LR\n  A --")
        #expect(blocks.count == 2)
        #expect(blocks[1] == .mermaid("flowchart LR\n  A --"))
        // A bare "#" or "#hashtag" is not a heading.
        #expect(MarkdownBlocks.split("#tag here") == [.paragraph("#tag here")])
        #expect(MarkdownBlocks.split("#") == [.paragraph("#")])
    }

    @Test func markdownShowsPythonFenceAsWrappingCode() {
        let text = """
        Here's a simple **Python** implementation:

        ```python
        def fibonacci(n):
            sequence = []
            a, b = 0, 1
            for _ in range(n):
                sequence.append(a)
                a, b = b, a + b
            return sequence
        print(fibonacci(10))
        ```

        Output:
        """
        let blocks = MarkdownBlocks.split(text)
        #expect(blocks.count == 3)
        #expect(blocks[0] == .paragraph("Here's a simple **Python** implementation:"))
        guard case .code(let language, let body) = blocks[1] else {
            Issue.record("expected a python code block")
            return
        }
        #expect(language == "python")
        #expect(body.contains("def fibonacci(n):"))
        #expect(body.contains("return sequence"))
        #expect(blocks[2] == .paragraph("Output:"))
        #expect(MarkdownBlocks.split("Before\n```\n[0, 1, 1, 2]\n```\nAfter") == [
            .paragraph("Before"),
            .code(language: "", "[0, 1, 1, 2]"),
            .paragraph("After")
        ])
    }

    @Test func mermaidZoomPanClampsAndUnlocksDragAfterOverflow() {
        var zoom = MermaidZoomPan()
        let size = CGSize(width: 200, height: 100)
        zoom.pan(by: CGSize(width: 40, height: 10), in: size)
        #expect(zoom.scale == 1)
        #expect(zoom.offset == .zero)
        #expect(!zoom.canPan)

        zoom.zoom(by: 2, toward: CGPoint(x: 100, y: 50), in: size)
        #expect(zoom.scale == 2)
        #expect(zoom.offset == .zero)
        #expect(zoom.canPan)

        zoom.pan(by: CGSize(width: 1000, height: 1000), in: size)
        #expect(zoom.offset.width == 100)
        #expect(zoom.offset.height == 50)

        zoom.reset()
        #expect(zoom.scale == 1)
        #expect(zoom.offset == .zero)
    }

    @Test func mermaidZoomKeepsPointUnderCursor() {
        var zoom = MermaidZoomPan()
        let size = CGSize(width: 200, height: 100)
        zoom.zoom(by: 2, toward: CGPoint(x: 0, y: 50), in: size)
        #expect(zoom.scale == 2)
        #expect(zoom.offset.width == 100)
        #expect(abs(zoom.offset.height) < 0.001)

        zoom.zoom(by: 10, toward: CGPoint(x: 100, y: 50), in: size)
        #expect(zoom.scale == MermaidZoomPan.maxScale)
    }
}

struct RenderingAndSummaryTests {
    @Test func markdownRendererReusesUnchangedBlocks() {
        let first = MarkdownRenderer.render("Intro **bold**\n\n```swift\nlet a = 1\n```\n\nTail", reusing: [])
        #expect(first.count == 3)
        let second = MarkdownRenderer.render("Intro **bold**\n\n```swift\nlet a = 1\n```\n\nTail more", reusing: first)
        #expect(second.count == 3)
        #expect(second[0] == first[0])
        #expect(second[1] == first[1])
        #expect(second[2] != first[2])
        if case .paragraph(let value) = second[0].kind {
            #expect(String(value.characters) == "Intro bold")
        } else {
            Issue.record("expected paragraph")
        }
    }

    @Test func threadSummaryAggregatesTurns() {
        let usage = TokenUsage(inputTokens: 1000, outputTokens: 200, cachedInputTokens: 600, cacheWriteTokens: 0, reasoningTokens: 50)
        let turns = [
            ChatTurn(id: UUID(), role: .user, content: "q1", createdAt: .now, status: .complete, attachments: []),
            ChatTurn(id: UUID(), role: .assistant, content: "a1", createdAt: .now, status: .complete, attachments: [],
                     usage: usage, costUsd: 0.01, webSearchCalls: 1,
                     timing: ResponseTiming(timeToFirstTokenMs: 400, totalMs: 2000), model: .sol, reasoningEffort: .low),
            ChatTurn(id: UUID(), role: .user, content: "q2", createdAt: .now, status: .complete, attachments: []),
            ChatTurn(id: UUID(), role: .assistant, content: "a2", createdAt: .now, status: .complete, attachments: [],
                     usage: usage, costUsd: 0.02, webSearchCalls: 0,
                     timing: ResponseTiming(timeToFirstTokenMs: 600, totalMs: 3000), model: .mini, reasoningEffort: .none)
        ]
        let summary = ThreadSummary.build(from: turns)
        #expect(summary.userMessages == 2)
        #expect(summary.assistantMessages == 2)
        #expect(abs(summary.totalCostUsd - 0.03) < 1e-9)
        #expect(summary.inputTokens == 2000)
        #expect(summary.cachedInputTokens == 1200)
        #expect(summary.cacheHitRatio == 0.6)
        #expect(summary.reasoningTokens == 100)
        #expect(summary.webSearchCalls == 1)
        #expect(summary.models == [.sol, .mini])
        #expect(summary.averageFirstTokenMs == 500)
        #expect(summary.averageTotalMs == 2500)
        #expect(summary.turns.map(\.index) == [1, 2])
        #expect(ThreadSummary.formatTokens(12_345) == "12.3k")
        #expect(ThreadSummary.formatTokens(999) == "999")
        #expect(ThreadSummary.formatMs(1500) == "1.5s")
        #expect(ThreadSummary.formatMs(420) == "420ms")
    }
}
