import AppKit
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
        #expect(blocks[3] == .list(ordered: true, items: [
            ListItem(level: 0, marker: "1.", text: "Rider opens app"),
            ListItem(level: 0, marker: "2.", text: "Match")
        ]))
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

    @Test func mermaidZoomMathClampsAndConverts() {
        // Excalidraw's range: 10% to 3000%.
        #expect(MermaidZoom.clamp(0.02) == MermaidZoom.minScale)
        #expect(MermaidZoom.clamp(3) == 3)
        #expect(MermaidZoom.clamp(50) == MermaidZoom.maxScale)
        #expect(MermaidZoom.clamp(.nan) == 1)

        // One legacy notch doubles; 200 precise points double; negative halves.
        #expect(MermaidZoom.factor(forScrollDelta: 20, precise: false) == 2)
        #expect(MermaidZoom.factor(forScrollDelta: 200, precise: true) == 2)
        #expect(abs(MermaidZoom.factor(forScrollDelta: -20, precise: false) - 0.5) < 0.0001)

        // Trackpad points move the canvas as-is; a mouse notch in lines is widened.
        #expect(MermaidZoom.panPoints(scrollDeltaX: 10, scrollDeltaY: -4, precise: true) == CGSize(width: 10, height: -4))
        #expect(MermaidZoom.panPoints(scrollDeltaX: 1, scrollDeltaY: -3, precise: false) == CGSize(width: 10, height: -30))
        #expect(MermaidZoom.panPoints(scrollDeltaX: .nan, scrollDeltaY: 1, precise: true) == .zero)

        #expect(MermaidZoom.percent(0.724) == 72)
        #expect(MermaidZoom.percent(1) == 100)
        #expect(MermaidZoom.percent(.infinity) == 100)
    }

    @Test func mermaidInlineHeightFollowsTheDiagramWithinBounds() {
        #expect(MermaidCanvasLayout.inlineHeight(for: 300.2) == 301)
        #expect(MermaidCanvasLayout.inlineHeight(for: 20) == MermaidCanvasLayout.minHeight)
        #expect(MermaidCanvasLayout.inlineHeight(for: 5000) == MermaidCanvasLayout.maxHeight)
        #expect(MermaidCanvasLayout.inlineHeight(for: .nan) == MermaidCanvasLayout.defaultHeight)
    }

    @Test func codeLineNumbersFollowSourceLines() {
        #expect(CodeLineNumbers.lineStarts(in: "") == [0])
        #expect(CodeLineNumbers.lineStarts(in: "a\nbb\nccc") == [0, 2, 5])
        // A trailing newline leaves an empty final line, as an editor shows it.
        #expect(CodeLineNumbers.lineStarts(in: "a\n") == [0, 2])
        // Offsets count UTF-16 units, the way TextKit addresses characters.
        #expect(CodeLineNumbers.lineStarts(in: "😀\nx") == [0, 3])

        // At least two digits of room, then one more per order of magnitude.
        let two = CodeLineNumbers.gutterWidth(lineCount: 9, digitWidth: 7)
        #expect(two == 14 + CodeLineNumbers.leadingInset + CodeLineNumbers.trailingInset)
        #expect(CodeLineNumbers.gutterWidth(lineCount: 99, digitWidth: 7) == two)
        #expect(CodeLineNumbers.gutterWidth(lineCount: 100, digitWidth: 7) == two + 7)
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

struct SelectableTextTests {
    @Test func builderMapsInlineIntentsToFonts() {
        let blocks = MarkdownRenderer.render("Plain **bold** and *italic* and `code` here", reusing: [])
        let text = MarkdownTextBuilder.build(blocks)
        let string = text.string
        func font(at needle: String) -> NSFont? {
            guard let range = string.range(of: needle) else { return nil }
            return text.attribute(.font, at: NSRange(range, in: string).location, effectiveRange: nil) as? NSFont
        }
        #expect(string == "Plain bold and italic and code here")
        #expect(font(at: "bold")?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font(at: "italic")?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(font(at: "Plain")?.fontDescriptor.symbolicTraits.contains(.bold) == false)
        #expect(font(at: "code")?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    @Test func builderStylesHeadingsAndCodeBlocks() {
        let blocks = MarkdownRenderer.render("## Title\n\nBody\n\n```swift\nlet a = 1\n```", reusing: [])
        let text = MarkdownTextBuilder.build(blocks)
        let string = text.string
        #expect(string == "Title\nBody\nlet a = 1")
        let heading = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(heading?.pointSize == MarkdownTextBuilder.headingSize(2))
        let codeLocation = NSRange(string.range(of: "let a")!, in: string).location
        let style = text.attribute(.paragraphStyle, at: codeLocation, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.textBlocks.count == 1)
        let codeFont = text.attribute(.font, at: codeLocation, effectiveRange: nil) as? NSFont
        #expect(codeFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        // Plain body paragraphs carry no text block.
        let bodyLocation = NSRange(string.range(of: "Body")!, in: string).location
        let bodyStyle = text.attribute(.paragraphStyle, at: bodyLocation, effectiveRange: nil) as? NSParagraphStyle
        #expect(bodyStyle?.textBlocks.isEmpty == true)
    }

    @Test func segmentsSplitAtCodeAndMermaid() {
        let blocks = MarkdownRenderer.render("Intro\n\n```swift\nx\n```\n\n```mermaid\nflowchart LR\n```\n\nOutro", reusing: [])
        let segments = MessageSegment.group(blocks)
        #expect(segments.count == 4)
        guard case .text(_, let first) = segments[0],
              case .code(_, let language, let code, _) = segments[1],
              case .mermaid(_, let diagram) = segments[2],
              case .text(_, let last) = segments[3]
        else {
            Issue.record("unexpected segment layout")
            return
        }
        #expect(first.count == 1)
        #expect(language == "swift")
        #expect(code == "x")
        #expect(diagram == "flowchart LR")
        #expect(last.count == 1)
    }

    @Test func codeLanguageLabelsFallBackToTheFence() {
        #expect(CodeLanguage.label(for: "py") == "Python")
        #expect(CodeLanguage.label(for: "TS") == "TypeScript")
        #expect(CodeLanguage.label(for: "brainfuck") == "brainfuck")
    }
}
