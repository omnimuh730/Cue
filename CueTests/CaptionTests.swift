import Foundation
import Testing
@testable import Cue

struct CaptionLineAssemblerTests {
    @Test func splitsOnLineBreaks() {
        let parts = CaptionLineAssembler.splitLines("hello\nworld\r\nthird\u{2028}fourth")
        #expect(parts == ["hello", "world", "third", "fourth"])
    }

    @Test func growsTheLiveLineInPlace() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("Hel")
        assembler.ingest("Hello")
        assembler.ingest("Hello there")
        #expect(assembler.lines.count == 1)
        #expect(assembler.lines[0].text == "Hello there")
        #expect(assembler.lines[0].isLive)
    }

    @Test func startsANewLineAfterALineBreak() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("Hello there")
        assembler.ingest("Hello there\nHow are you")
        #expect(assembler.lines.count == 2)
        #expect(assembler.lines[0].text == "Hello there")
        #expect(assembler.lines[0].isLive == false)
        #expect(assembler.lines[1].text == "How are you")
        #expect(assembler.lines[1].isLive)
    }

    @Test func commitsEachOverlayLineAndKeepsTheLastLive() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("One\nTwo\nThree")
        #expect(assembler.lines.map(\.text) == ["One", "Two", "Three"])
        #expect(assembler.lines.map(\.isLive) == [false, false, true])
    }

    @Test func ignoresEmptySnapshotsSoHistoryRemains() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("Kept line")
        assembler.ingest("   \n")
        #expect(assembler.lines.map(\.text) == ["Kept line"])
    }

    @Test func sameSnapshotIsANoOp() {
        var assembler = CaptionLineAssembler()
        #expect(assembler.ingest("Stable") == true)
        let id = assembler.lines[0].id
        #expect(assembler.ingest("Stable") == false)
        #expect(assembler.lines[0].id == id)
    }

    @Test func collapsesGrowingPrefixesFromOneAXSnapshot() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("""
        Live Captions Running
        I talk a lot about this spotot that I built
        I talk a lot about this spotot that I built called Benny and
        I talk a lot about this spotot that I built called Benny and I wanted to
        I talk a lot about this bot that I built called Benny, and I wanted to figure out how would I make it so my agents can just automatically fix bugs for me while I sleep?
        """)
        #expect(assembler.lines.count == 1)
        #expect(assembler.lines[0].isLive)
        #expect(assembler.lines[0].text.contains("fix bugs for me while I sleep"))
        #expect(assembler.lines[0].text.contains("Live Captions") == false)
    }

    @Test func growingPartialsUpdateTheLiveLineInsteadOfStacking() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("I talk a lot about this spotot that I built")
        assembler.ingest("I talk a lot about this spotot that I built called Benny and")
        assembler.ingest("I talk a lot about this spotot that I built called Benny and I wanted to figure out how would I")
        assembler.ingest("I talk a lot about this bot that I built called Benny, and I wanted to figure out how would I make it so my agents")
        #expect(assembler.lines.count == 1)
        #expect(assembler.lines[0].isLive)
        #expect(assembler.lines[0].text.contains("called Benny"))
    }

    @Test func commitsWhenANewUtteranceAppears() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("I talk a lot about this bot that I built called Benny")
        assembler.ingest("""
        I talk a lot about this bot that I built called Benny, and I wanted to figure out how would I make it so my agents can just automatically fix bugs for me while I sleep?
        And so that was the inspiration for some of our earlier experiments, like you know, what if everybody could define one of their own
        """)
        #expect(assembler.lines.count == 2)
        #expect(assembler.lines[0].isLive == false)
        #expect(assembler.lines[0].text.contains("fix bugs for me while I sleep"))
        #expect(assembler.lines[1].isLive)
        #expect(assembler.lines[1].text.hasPrefix("And so that was the inspiration"))
    }

    @Test func dropsLiveCaptionsChrome() {
        #expect(CaptionTextMerge.isChrome("Live Captions Running"))
        #expect(CaptionTextMerge.collapse(["Live Captions Running", "Hello there"]) == ["Hello there"])
    }

    @Test func dropsMicrophoneOffChrome() {
        #expect(CaptionTextMerge.isChrome("Microphone Off"))
        #expect(CaptionTextMerge.isChrome("microphone off."))
        var assembler = CaptionLineAssembler()
        assembler.ingest("it's like super powerful.\nMicrophone Off\nIt runs even if you're not at your computer.")
        #expect(assembler.lines.map(\.text) == [
            "it's like super powerful.",
            "It runs even if you're not at your computer.",
        ])
    }

    @Test func scrolledOffOverlapCommitsTheStablePrefix() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("I talk a lot about this bot that I built called Benny and I wanted to figure out")
        assembler.ingest("called Benny and I wanted to figure out how would I make it so my agents")
        #expect(assembler.lines.count == 2)
        #expect(assembler.lines[0].isLive == false)
        #expect(assembler.lines[0].text.contains("I talk a lot about this bot"))
        #expect(assembler.lines[1].isLive)
        #expect(assembler.lines[1].text.hasPrefix("called Benny"))
    }

    @Test func replacesLiveChunkOnPunctuationAndSmallGrowth() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("The max which we have")
        assembler.ingest("The max which we have\nThe max which we have $130,000 per a year.")
        assembler.ingest("Should I quote you")
        assembler.ingest("Should I quote you?")
        assembler.ingest("So just be here")
        assembler.ingest("So just be here with me.")
        #expect(assembler.lines.map(\.text) == [
            "The max which we have $130,000 per a year.",
            "Should I quote you?",
            "So just be here with me.",
        ])
        #expect(assembler.lines.last?.isLive == true)
    }

    @Test func doesNotStackWhenAXTreeKeepsEveryPartial() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("if the client also have")
        assembler.ingest("""
        if the client also have
        if the client also have avility uh
        if the client also have avility uh if they also are
        """)
        assembler.ingest("""
        if the client also have
        if the client also have avility uh
        if the client also have avility uh if they also are available at that time then they will schedule an interview with you over one of virtual longterm interview.
        If the client also have ability, uh if they also are available at that time, then they will schedule an interview with you over a virtual long-term interview.
        """)
        #expect(assembler.lines.count == 1)
        #expect(assembler.lines[0].isLive)
        #expect(assembler.lines[0].text.contains("long-term interview"))
    }

    @Test func cacheKeepsHistoryAfterOverlayScrolls() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("First sentence here.")
        assembler.ingest("First sentence here.\nSecond sentence here.")
        assembler.ingest("Second sentence here.\nThird sentence here.")
        #expect(assembler.lines.map(\.text) == [
            "First sentence here.",
            "Second sentence here.",
            "Third sentence here.",
        ])
    }

    @Test func resetStartsANewCacheWithoutRehydratingOverlayHistory() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("Old one.")
        assembler.ingest("Old one.\nOld two.")
        assembler.reset()
        #expect(assembler.lines.isEmpty)
        assembler.ingest("""
        Old one.
        Old two.
        Brand new live
        """)
        #expect(assembler.lines.map(\.text) == ["Brand new live"])
        #expect(assembler.lines[0].isLive)
        assembler.ingest("""
        Old two.
        Brand new live continues now.
        """)
        #expect(assembler.lines.count == 1)
        #expect(assembler.lines[0].text.contains("Brand new live continues"))
    }
}

struct CaptionSentenceGrabTests {
    private func lines(_ texts: [String]) -> [CaptionLine] {
        texts.enumerated().map { index, text in
            CaptionLine(text: text, isLive: index == texts.count - 1)
        }
    }

    @Test func grabAllReturnsTheFullCache() {
        let cache = lines([
            "Hello there.",
            "How are you?",
            "I am fine!",
        ])
        #expect(CaptionSentenceGrab.grab(from: cache, count: 0) == "Hello there. How are you? I am fine!")
    }

    @Test func grabLastTwoSentencesMatchesNumpadOne() {
        let cache = lines([
            "First sentence.",
            "Second sentence.",
            "Third sentence.",
            "Fourth leftover",
        ])
        #expect(CaptionSentenceGrab.grab(from: cache, count: 2) == "Third sentence. Fourth leftover")
    }

    @Test func grabLastFourSentencesMatchesNumpadTwo() {
        let cache = lines([
            "One.",
            "Two.",
            "Three.",
            "Four.",
            "Five.",
        ])
        #expect(CaptionSentenceGrab.grab(from: cache, count: 4) == "Two. Three. Four. Five.")
    }

    @Test func grabReturnsWhatExistsWhenCacheIsShorter() {
        let cache = lines(["Only one sentence."])
        #expect(CaptionSentenceGrab.grab(from: cache, count: 18) == "Only one sentence.")
    }

    @Test func grabAllUsesTheUnboundedCache() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("Alpha sentence.")
        assembler.ingest("Alpha sentence.\nBeta sentence.")
        assembler.ingest("Beta sentence.\nGamma sentence.")
        #expect(
            CaptionSentenceGrab.grab(from: assembler.lines, count: 0)
                == "Alpha sentence. Beta sentence. Gamma sentence."
        )
        assembler.reset()
        #expect(CaptionSentenceGrab.grab(from: assembler.lines, count: 0) == nil)
    }

    @Test func keepsTrailingPunctuation() {
        let text = "Are you there? Yes. Wow!"
        #expect(CaptionSentenceGrab.sentences(in: text) == ["Are you there?", "Yes.", "Wow!"])
    }

    @Test func orderedSentencesKeepTheLiveFragment() {
        let cache = [
            CaptionLine(text: "Hello, how are you doing?", isLive: false),
            CaptionLine(text: "Good. Still talking", isLive: true),
        ]
        #expect(
            CaptionSentenceGrab.orderedSentences(from: cache)
                == ["Hello, how are you doing?", "Good.", "Still talking"]
        )
    }
}

struct CaptionDraftSyncTests {
    @Test func growingLiveLineReplacesInsteadOfAppending() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("Hello")
        var draft = ""
        var snapshot = ""

        var applied = CaptionDraftSync.apply(snapshot: assembler.lines, to: draft, previousSnapshot: snapshot)
        draft = applied.draft
        snapshot = applied.snapshot
        assembler.ingest("Hello there")
        applied = CaptionDraftSync.apply(snapshot: assembler.lines, to: draft, previousSnapshot: snapshot)
        draft = applied.draft
        snapshot = applied.snapshot
        assembler.ingest("Hello there everyone.")
        applied = CaptionDraftSync.apply(snapshot: assembler.lines, to: draft, previousSnapshot: snapshot)

        #expect(applied.draft == "Hello there everyone.")
        #expect(applied.draft.contains("Hello Hello") == false)
    }

    @Test func committedSentencesStayOnceAndLiveRevisesInPlace() {
        var assembler = CaptionLineAssembler()
        assembler.ingest("First sentence here.")
        assembler.ingest("First sentence here.\nSecond sentence here.")
        assembler.ingest("Second sentence here.\nThird leftover")

        var draft = ""
        var snapshot = ""
        var applied = CaptionDraftSync.apply(snapshot: assembler.lines, to: draft, previousSnapshot: snapshot)
        draft = applied.draft
        snapshot = applied.snapshot
        #expect(draft == "First sentence here. Second sentence here. Third leftover")

        assembler.ingest("Second sentence here.\nThird leftover grows")
        applied = CaptionDraftSync.apply(snapshot: assembler.lines, to: draft, previousSnapshot: snapshot)
        #expect(applied.draft == "First sentence here. Second sentence here. Third leftover grows")
    }

    @Test func keepsUserTypedPrefix() {
        let next = CaptionDraftSync.replace(in: "notes Hello", previous: "Hello", next: "Hello there")
        #expect(next == "notes Hello there")
    }
}
