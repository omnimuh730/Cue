import AppKit
import Testing
@testable import Cue

struct MarkdownBlockSplitTests {
    @Test func bulletsNestAndTaskBoxesBecomeMarkers() {
        let text = """
        Steps:
        - First
          - Nested *deep*
            - Deeper
        * [ ] todo
        * [x] done
        + plus works too
        """
        let blocks = MarkdownBlocks.split(text)
        #expect(blocks.count == 2)
        #expect(blocks[0] == .paragraph("Steps:"))
        #expect(blocks[1] == .list(ordered: false, items: [
            ListItem(level: 0, marker: "•", text: "First"),
            ListItem(level: 1, marker: "•", text: "Nested *deep*"),
            ListItem(level: 2, marker: "•", text: "Deeper"),
            ListItem(level: 0, marker: "☐", text: "todo"),
            ListItem(level: 0, marker: "☑", text: "done"),
            ListItem(level: 0, marker: "•", text: "plus works too")
        ]))
    }

    @Test func orderedListsKeepTheirNumbersAndWrapContinuations() {
        let blocks = MarkdownBlocks.split("1. One\n2. Two\nstill two\n10) Ten\n\nAfter")
        #expect(blocks == [
            .list(ordered: true, items: [
                ListItem(level: 0, marker: "1.", text: "One"),
                ListItem(level: 0, marker: "2.", text: "Two\nstill two"),
                ListItem(level: 0, marker: "10.", text: "Ten")
            ]),
            .paragraph("After")
        ])
    }

    @Test func proseThatLooksLikeMarkersStaysProse() {
        // "-foo" has no space, "3.14" is a number, "2024. A year" cannot break into a paragraph.
        #expect(MarkdownBlocks.split("-foo bar") == [.paragraph("-foo bar")])
        #expect(MarkdownBlocks.split("3.14 is pi") == [.paragraph("3.14 is pi")])
        #expect(MarkdownBlocks.split("In\n2024. A year") == [.paragraph("In\n2024. A year")])
        // "1." may.
        #expect(MarkdownBlocks.split("Plan:\n1. Go") == [
            .paragraph("Plan:"),
            .list(ordered: true, items: [ListItem(level: 0, marker: "1.", text: "Go")])
        ])
    }

    @Test func fenceInsideAListIsNotSwallowed() {
        let blocks = MarkdownBlocks.split("- run it\n```sh\nmake\n```\n- done")
        #expect(blocks == [
            .list(ordered: false, items: [ListItem(level: 0, marker: "•", text: "run it")]),
            .code(language: "sh", "make"),
            .list(ordered: false, items: [ListItem(level: 0, marker: "•", text: "done")])
        ])
    }

    @Test func aSentenceThatOnlyStartsWithBackticksStaysProse() {
        // A fence opened here would never close, swallowing the rest of the answer into a code
        // block whose "language" is the rest of the sentence.
        let blocks = MarkdownBlocks.split("""
        Fibonacci in short:

        ```text``` marks plain output, so here it is:

        0, 1, 1, 2, 3, 5, 8

        Each number is the sum of the two before it.
        """)
        #expect(blocks == [
            .paragraph("Fibonacci in short:"),
            .paragraph("```text``` marks plain output, so here it is:"),
            .paragraph("0, 1, 1, 2, 3, 5, 8"),
            .paragraph("Each number is the sum of the two before it.")
        ])
    }

    @Test func realFencesStillOpen() {
        #expect(MarkdownBlocks.fenceInfo("```swift") == "swift")
        #expect(MarkdownBlocks.fenceInfo("```  Text ") == "text")
        // No language at all is still a fence.
        #expect(MarkdownBlocks.fenceInfo("```") == "")
        #expect(MarkdownBlocks.fenceInfo("``text``") == nil)
        #expect(MarkdownBlocks.fenceInfo("nope ```swift") == nil)
    }

    @Test func proseAfterAClosedFenceSurvives() {
        let blocks = MarkdownBlocks.split("Intro:\n\n```text\n0, 1, 1, 2\n```\n\nEach is the sum of two.")
        #expect(blocks == [
            .paragraph("Intro:"),
            .code(language: "text", "0, 1, 1, 2"),
            .paragraph("Each is the sum of two.")
        ])
    }

    @Test func quotesJoinLinesAndEndAtProse() {
        let blocks = MarkdownBlocks.split("> A quote\n> continues\n>\n> second para\nBack to prose")
        #expect(blocks == [
            .blockquote("A quote\ncontinues\n\nsecond para"),
            .paragraph("Back to prose")
        ])
    }

    @Test func rulesAreRecognisedButNotTableSeparators() {
        #expect(MarkdownBlocks.split("a\n\n---\n\nb") == [.paragraph("a"), .rule, .paragraph("b")])
        #expect(MarkdownBlocks.split("* * *") == [.rule])
        #expect(MarkdownBlocks.split("___") == [.rule])
        #expect(MarkdownBlocks.split("--") == [.paragraph("--")])
        #expect(MarkdownBlocks.isRule("|---|") == false)
    }

    @Test func tablesNeedASeparatorAndPadShortRows() {
        let text = """
        | Name | Qty | Price |
        |:-----|:---:|------:|
        | Apple | 3 | 1.20 |
        | Pear | 1
        Done
        """
        let blocks = MarkdownBlocks.split(text)
        #expect(blocks == [
            .table(
                header: ["Name", "Qty", "Price"],
                alignments: [.left, .center, .right],
                rows: [["Apple", "3", "1.20"], ["Pear", "1", ""]]
            ),
            .paragraph("Done")
        ])
    }

    @Test func aStreamingTableHeaderStaysProseUntilItsSeparatorArrives() {
        #expect(MarkdownBlocks.split("| a | b |") == [.paragraph("| a | b |")])
        #expect(MarkdownBlocks.split("| a | b |\n| c | d |") == [.paragraph("| a | b |\n| c | d |")])
        #expect(MarkdownBlocks.split("| a | b |\n|---|---|") == [.table(header: ["a", "b"], alignments: [.left, .left], rows: [])])
        // A pipe mid-sentence is prose.
        #expect(MarkdownBlocks.split("either | or") == [.paragraph("either | or")])
    }

    @Test func escapedPipesStayInsideCells() {
        #expect(MarkdownBlocks.tableCells("| a \\| b | c |") == ["a | b", "c"])
    }
}

struct MarkdownBuilderTests {
    @Test func listItemsHangTheirTextUnderTheFirstWord() {
        let blocks = MarkdownRenderer.render("- one\n  - two", reusing: [])
        let text = MarkdownTextBuilder.build(blocks)
        #expect(text.string == "•\tone\n•\ttwo")
        let first = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(first?.firstLineHeadIndent == 0)
        #expect(first?.headIndent == MarkdownTextBuilder.listMarkerWidth)
        let secondLocation = (text.string as NSString).range(of: "two").location
        let second = text.attribute(.paragraphStyle, at: secondLocation, effectiveRange: nil) as? NSParagraphStyle
        #expect(second?.firstLineHeadIndent == MarkdownTextBuilder.listIndentStep)
        #expect(second?.headIndent == MarkdownTextBuilder.listIndentStep + MarkdownTextBuilder.listMarkerWidth)
    }

    @Test func quotesAreTaggedAndIndentedAsOneRun() throws {
        let blocks = MarkdownRenderer.render("Intro\n\n> a\n> b\n>\n> c", reusing: [])
        let text = MarkdownTextBuilder.build(blocks)
        let string = text.string as NSString
        // Lines inside the quote are line separators, not paragraph breaks, so the tag and the
        // indent run unbroken from "a" to "c" and the bar is drawn as one piece.
        #expect(string.contains("a\u{2028}b\u{2028}\u{2028}c"))
        var effective = NSRange()
        let location = string.range(of: "a\u{2028}b").location
        try #require(location != NSNotFound)
        let tagged = text.attribute(
            MarkdownTextBuilder.quoteAttribute,
            at: location,
            longestEffectiveRange: &effective,
            in: NSRange(location: 0, length: text.length)
        ) as? Bool
        #expect(tagged == true)
        #expect(effective == NSRange(location: location, length: text.length - location))
        let style = text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.headIndent == MarkdownTextBuilder.quoteInset)
        #expect(style?.firstLineHeadIndent == MarkdownTextBuilder.quoteInset)
        let color = text.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.secondaryLabelColor)
        // The paragraph before the quote is not tagged.
        #expect(text.attribute(MarkdownTextBuilder.quoteAttribute, at: 0, effectiveRange: nil) == nil)
    }

    @Test func rulesAreShortTaggedParagraphs() {
        let text = MarkdownTextBuilder.build(MarkdownRenderer.render("a\n\n---\n\nb\n\n---", reusing: []))
        #expect(text.string == "a\n\u{00A0}\nb\n\u{00A0}")
        #expect(text.attribute(MarkdownTextBuilder.ruleAttribute, at: 2, effectiveRange: nil) as? Bool == true)
        #expect(text.attribute(MarkdownTextBuilder.ruleAttribute, at: text.length - 1, effectiveRange: nil) as? Bool == true)
        #expect(text.attribute(MarkdownTextBuilder.ruleAttribute, at: 0, effectiveRange: nil) == nil)
        #expect(text.attribute(MarkdownTextBuilder.ruleAttribute, at: 4, effectiveRange: nil) == nil)
    }

    @Test func tablesBecomeTextTables() {
        let blocks = MarkdownRenderer.render("| h1 | h2 |\n|---|--:|\n| x | y |\n\nAfter", reusing: [])
        let text = MarkdownTextBuilder.build(blocks)
        let string = text.string as NSString
        #expect(string.hasPrefix("h1\nh2\nx\ny\nAfter"))
        let cell = text.attribute(.paragraphStyle, at: string.range(of: "h1").location, effectiveRange: nil) as? NSParagraphStyle
        let block = cell?.textBlocks.first as? NSTextTableBlock
        #expect(block?.table.numberOfColumns == 2)
        #expect(block?.startingRow == 0)
        #expect(block?.startingColumn == 0)
        let header = text.attribute(.font, at: string.range(of: "h1").location, effectiveRange: nil) as? NSFont
        #expect(header?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let body = text.attribute(.paragraphStyle, at: string.range(of: "y").location, effectiveRange: nil) as? NSParagraphStyle
        let bodyBlock = body?.textBlocks.first as? NSTextTableBlock
        #expect(bodyBlock?.startingRow == 1)
        #expect(bodyBlock?.startingColumn == 1)
        #expect(bodyBlock?.table === block?.table)
        #expect(body?.alignment == .right)
        let after = text.attribute(.paragraphStyle, at: string.range(of: "After").location, effectiveRange: nil) as? NSParagraphStyle
        #expect(after?.textBlocks.isEmpty == true)
    }

    @Test func listContinuationsAreLineSeparators() {
        let text = MarkdownTextBuilder.build(MarkdownRenderer.render("1. One\nmore", reusing: []))
        #expect(text.string == "1.\tOne\u{2028}more")
    }

    @Test func codeColorsFollowSpans() {
        let source = "let x = \"hi\""
        let spans = CodeHighlighter.spans(source, language: "swift")
        let text = MarkdownTextBuilder.code(source, spans: spans)
        #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == CodeTheme.color(for: .keyword))
        #expect(text.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor == NSColor.labelColor)
        #expect(text.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor == CodeTheme.color(for: .string))
        // Out-of-range spans (stale from a previous flush) are ignored rather than crashing.
        let stale = MarkdownTextBuilder.code("ab", spans: [HighlightSpan(range: 0..<5, token: .keyword)])
        #expect(stale.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.labelColor)
    }

    @Test func rendererCachesSpansWithTheBlock() {
        let first = MarkdownRenderer.render("```swift\nlet a = 1\n```", reusing: [])
        guard case .code(let language, let source, let spans) = first[0].kind else {
            Issue.record("expected code")
            return
        }
        #expect(language == "swift")
        #expect(source == "let a = 1")
        #expect(spans.contains(HighlightSpan(range: 0..<3, token: .keyword)))
        let second = MarkdownRenderer.render("```swift\nlet a = 1\n```\n\nmore", reusing: first)
        #expect(second[0].kind == first[0].kind)
    }
}

struct CodeHighlighterTests {
    private func tokens(_ source: String, _ language: String) -> [(String, HighlightToken)] {
        let units = Array(source.utf16)
        return CodeHighlighter.spans(source, language: language).map { span in
            (String(utf16CodeUnits: Array(units[span.range]), count: span.range.count), span.token)
        }
    }

    @Test func swiftKeywordsStringsCommentsNumbersTypesAndAttributes() {
        let source = """
        // note
        @MainActor func go(_ count: Int) -> String { return "n=\\(count)" } /* done */ let x = 0x1F + 2.5
        """
        let found = tokens(source, "swift")
        #expect(found.contains { $0 == ("// note", .comment) })
        #expect(found.contains { $0 == ("@MainActor", .attribute) })
        #expect(found.contains { $0 == ("func", .keyword) })
        #expect(found.contains { $0 == ("Int", .type) })
        #expect(found.contains { $0 == ("String", .type) })
        #expect(found.contains { $0 == ("return", .keyword) })
        #expect(found.contains { $0 == ("\"n=\\(count)\"", .string) })
        #expect(found.contains { $0 == ("/* done */", .comment) })
        #expect(found.contains { $0 == ("0x1F", .number) })
        #expect(found.contains { $0 == ("2.5", .number) })
        // `go` and `count` are plain identifiers.
        #expect(!found.contains { $0.0 == "go" || $0.0 == "count" })
    }

    @Test func pythonTripleQuotesAndDecorators() {
        let source = "@dataclass\nclass Point:\n    \"\"\"doc\n    string\"\"\"\n    def __init__(self): pass  # end"
        let found = tokens(source, "python")
        #expect(found.contains { $0 == ("@dataclass", .attribute) })
        #expect(found.contains { $0 == ("class", .keyword) })
        #expect(found.contains { $0 == ("Point", .type) })
        #expect(found.contains { $0 == ("\"\"\"doc\n    string\"\"\"", .string) })
        #expect(found.contains { $0 == ("def", .keyword) })
        #expect(found.contains { $0 == ("# end", .comment) })
    }

    @Test func shellVariablesAndComments() {
        let found = tokens("export FOO=\"$HOME/x\" # set\necho ${FOO} a#b", "bash")
        #expect(found.contains { $0 == ("export", .keyword) })
        #expect(found.contains { $0 == ("\"$HOME/x\"", .string) })
        #expect(found.contains { $0 == ("# set", .comment) })
        #expect(found.contains { $0 == ("${FOO}", .attribute) })
        // `#` inside a word is not a comment.
        #expect(!found.contains { $0.0 == "#b" })
    }

    @Test func jsonKeysDifferFromStringValues() {
        let found = tokens("{\"name\": \"cue\", \"n\": 3, \"ok\": true}", "json")
        #expect(found.contains { $0 == ("\"name\"", .attribute) })
        #expect(found.contains { $0 == ("\"cue\"", .string) })
        #expect(found.contains { $0 == ("3", .number) })
        #expect(found.contains { $0 == ("true", .keyword) })
    }

    @Test func htmlTagsAndAttributes() {
        let found = tokens("<div class=\"a\">hi</div><!-- c --><br/>", "html")
        #expect(found.contains { $0 == ("<div", .tag) })
        #expect(found.contains { $0 == ("class", .attribute) })
        #expect(found.contains { $0 == ("\"a\"", .string) })
        #expect(found.contains { $0 == ("</div", .tag) })
        #expect(found.contains { $0 == ("<!-- c -->", .comment) })
        #expect(!found.contains { $0.0 == "hi" })
    }

    @Test func sqlIsCaseInsensitive() {
        let found = tokens("SELECT id FROM users WHERE name = 'x' -- all", "sql")
        #expect(found.contains { $0 == ("SELECT", .keyword) })
        #expect(found.contains { $0 == ("FROM", .keyword) })
        #expect(found.contains { $0 == ("'x'", .string) })
        #expect(found.contains { $0 == ("-- all", .comment) })
        #expect(!found.contains { $0.0 == "users" })
    }

    @Test func unterminatedStringsAndUnknownLanguagesAreSafe() {
        let streaming = tokens("let s = \"not yet", "swift")
        #expect(streaming.contains { $0 == ("\"not yet", .string) })
        #expect(tokens("", "swift").isEmpty)
        #expect(CodeHighlighter.spans("x", language: "").isEmpty)
        // Unknown languages only get strings and numbers; `#` is not assumed to be a comment.
        let unknown = tokens("# heading 42 \"q\"", "brainfuck")
        #expect(unknown.contains { $0 == ("42", .number) })
        #expect(unknown.contains { $0 == ("\"q\"", .string) })
        #expect(!unknown.contains { $0.1 == .comment })
    }

    @Test func hugeBlocksAreLeftPlain() {
        let big = String(repeating: "let a = 1\n", count: 3_000)
        #expect(big.utf16.count > CodeHighlighter.maxLength)
        #expect(CodeHighlighter.spans(big, language: "swift").isEmpty)
    }

    @Test func spansNeverOverlapAndStayInBounds() {
        let source = "fn main() { let s = \"a\\\"b\"; /* x */ println!(\"{}\", 1); } // end"
        let spans = CodeHighlighter.spans(source, language: "rust")
        var last = 0
        for span in spans {
            #expect(span.range.lowerBound >= last)
            #expect(span.range.upperBound <= source.utf16.count)
            last = span.range.upperBound
        }
        #expect(!spans.isEmpty)
    }
}
