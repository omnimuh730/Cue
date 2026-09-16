import AppKit
import Foundation
import Testing
@testable import Cue

/// The character wipe that replaces 40 ms slabs of text with a smooth reveal.
struct StreamingRevealTests {
    @Test func rampRisesFromTheNewestCharacterBack() {
        #expect(StreamingTextReveal.alpha(distance: 0, span: 4) < 0.2)
        #expect(StreamingTextReveal.alpha(distance: 3, span: 4) == 1)
        #expect(StreamingTextReveal.alpha(distance: 9, span: 4) == 1)
        // Monotonic: older characters are never fainter than newer ones.
        let ramp = (0..<6).map { StreamingTextReveal.alpha(distance: $0, span: 6) }
        #expect(ramp == ramp.sorted())
    }

    @Test func revealWithholdsTheTailAndLeavesFinishedTextAlone() {
        let full = MarkdownTextBuilder.plain("abcdefghij")
        #expect(StreamingTextReveal.apply(full, reveal: nil).string == "abcdefghij")
        #expect(StreamingTextReveal.apply(full, reveal: 20).string == "abcdefghij")
        #expect(StreamingTextReveal.apply(full, reveal: 4).string == "abcd")
        #expect(StreamingTextReveal.apply(full, reveal: 0).length == 0)
    }

    @Test func revealNeverCutsInsideAnEmoji() {
        let full = MarkdownTextBuilder.plain("ok👩‍👩‍👧‍👦!")
        for cut in 0...full.length {
            let shown = StreamingTextReveal.apply(full, reveal: cut)
            // A split cluster would leave a lone surrogate, which is not valid on its own.
            #expect(shown.string.unicodeScalars.allSatisfy { !($0.value >= 0xD800 && $0.value <= 0xDFFF) })
            #expect(full.string.hasPrefix(shown.string))
        }
    }

    @Test func pacingCatchesUpWithoutStalling() {
        #expect(RevealPacing.advance(10, toward: 10) == 10)
        #expect(RevealPacing.advance(12, toward: 10) == 10)
        // A trickle still moves, and never past what has arrived.
        #expect(RevealPacing.advance(0, toward: 1) > 0)
        #expect(RevealPacing.advance(0, toward: 1) <= 1)
        #expect(RevealPacing.advance(0, toward: 100) > RevealPacing.minimumStep)
        // A backlog nobody could read through is taken in one step.
        #expect(RevealPacing.advance(0, toward: RevealPacing.jumpThreshold + 1) == RevealPacing.jumpThreshold + 1)
        // Chasing a live stream converges rather than oscillating.
        var shown = 0.0
        for _ in 0..<400 { shown = RevealPacing.advance(shown, toward: 500) }
        #expect(shown == 500)
    }
}

/// Patching an already laid-out message instead of rebuilding it is what keeps streaming smooth,
/// so the boundary it picks has to be safe as well as small.
struct IncrementalTextTests {
    private func text(_ value: String) -> NSAttributedString { MarkdownTextBuilder.plain(value) }

    @Test func appendingOnlyRewritesTheEnd() {
        let current = text(String(repeating: "a", count: 500))
        let next = text(String(repeating: "a", count: 520))
        let stable = IncrementalText.stablePrefix(of: current, and: next, volatileTail: 0)
        #expect(stable == 500 - IncrementalText.guardBand)
    }

    @Test func aChangedCharacterPullsTheBoundaryBackToIt() {
        let current = text("hello world, this is a sentence")
        let next = text("hello WORLD, this is a sentence")
        let stable = IncrementalText.stablePrefix(of: current, and: next, volatileTail: 0)
        #expect(stable <= 6)
    }

    @Test func theFadeRampIsNeverLeftBehind() {
        // The bug this guards: the reveal head catches up, the ramp stops being applied, and the
        // characters it dimmed keep their alpha because their glyphs did not change.
        let faded = StreamingTextReveal.apply(text("a sentence long enough to ramp"), reveal: 24)
        let solid = text("a sentence long enough to ramp")
        let stable = IncrementalText.stablePrefix(
            of: faded,
            and: solid,
            volatileTail: StreamingTextReveal.fadeSpan
        )
        #expect(stable <= faded.length - StreamingTextReveal.fadeSpan)
    }

    @Test func emptyAndShorterCasesStayInBounds() {
        #expect(IncrementalText.stablePrefix(of: text(""), and: text("abc"), volatileTail: 0) == 0)
        #expect(IncrementalText.stablePrefix(of: text("abc"), and: text(""), volatileTail: 0) == 0)
        let stable = IncrementalText.stablePrefix(of: text("abcdef"), and: text("abc"), volatileTail: 0)
        #expect(stable >= 0 && stable <= 3)
    }
}

/// Block attributes must not depend on what comes after them, or a streaming append would have to
/// relay out everything before it.
struct MarkdownBuilderStabilityTests {
    @Test func earlierBlocksAreUntouchedWhenAnotherArrives() {
        let first = MarkdownTextBuilder.build(MarkdownRenderer.render("One\n\nTwo", reusing: []))
        let second = MarkdownTextBuilder.build(MarkdownRenderer.render("One\n\nTwo\n\nThree", reusing: []))
        #expect(second.string.hasPrefix(first.string))
        let prefix = second.attributedSubstring(from: NSRange(location: 0, length: first.length))
        #expect(prefix.isEqual(to: first))
    }
}

/// Prompter order flips exchanges, never the question/answer pair inside one.
struct ReadingOrderTests {
    private struct Turn: Equatable { var text: String; var user: Bool }

    private let thread = [
        Turn(text: "q1", user: true), Turn(text: "a1", user: false),
        Turn(text: "q2", user: true), Turn(text: "a2", user: false), Turn(text: "a2b", user: false),
        Turn(text: "q3", user: true)
    ]

    @Test func chatOrderIsChronological() {
        let arranged = ReadingOrder.newestAtBottom.arrange(thread, isUser: \.user)
        #expect(arranged.map(\.text) == ["q1", "a1", "q2", "a2", "a2b", "q3"])
    }

    @Test func prompterOrderPutsTheNewestExchangeFirst() {
        let arranged = ReadingOrder.newestAtTop.arrange(thread, isUser: \.user)
        #expect(arranged.map(\.text) == ["q3", "q2", "a2", "a2b", "q1", "a1"])
    }

    @Test func prompterOrderKeepsALeadingReplyWithoutAQuestion() {
        let orphaned = [Turn(text: "a0", user: false)] + thread.prefix(2)
        let arranged = ReadingOrder.newestAtTop.arrange(orphaned, isUser: \.user)
        #expect(arranged.map(\.text) == ["q1", "a1", "a0"])
        #expect(ReadingOrder.newestAtTop.arrange([Turn](), isUser: \.user).isEmpty)
    }

    @Test func settingsSavedBeforeTheFieldStillDecode() throws {
        var settings = PublicSettings.default
        settings.readingOrder = .newestAtTop
        let data = try JSONEncoder().encode(settings)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["storedReadingOrder"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(PublicSettings.self, from: legacy)
        #expect(decoded.readingOrder == .newestAtBottom)
        #expect(try JSONDecoder().decode(PublicSettings.self, from: data).readingOrder == .newestAtTop)
    }
}
