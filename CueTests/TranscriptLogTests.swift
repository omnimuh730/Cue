import Foundation
import Testing
@testable import Cue

struct TranscriptLogTests {
    @Test func appendsCommittedSegmentsAndSkipsBlanks() {
        var log = TranscriptLog()
        log.append("  What is an actor? ")
        log.append("   ")
        log.append("And a class?")
        #expect(log.lines.map(\.text) == ["What is an actor?", "And a class?"])
        #expect(log.lines.allSatisfy { !$0.isLive })
    }

    @Test func capsAtTheLimitDroppingTheOldest() {
        var log = TranscriptLog()
        for index in 0..<(TranscriptLog.limit + 5) { log.append("line \(index)") }
        #expect(log.lines.count == TranscriptLog.limit)
        #expect(log.lines.first?.text == "line 5")
    }

    @Test func mirrorUpdatesLiveRowsInPlaceAndKeepsDroppedRowsAsHistory() {
        var log = TranscriptLog()
        let committed = CaptionLine(text: "First question.", isLive: false)
        var live = CaptionLine(text: "Second one is", isLive: true)
        log.mirror([committed, live])
        #expect(log.lines.map(\.text) == ["First question.", "Second one is"])
        #expect(log.lines.last?.isLive == true)

        // The live row keeps growing: same id, new text, still one row.
        live.text = "Second one is still going"
        log.mirror([committed, live])
        #expect(log.lines.count == 2)
        #expect(log.lines.last?.text == "Second one is still going")

        // After the assembler resets (new ids), its old rows stay here as committed history.
        let fresh = CaptionLine(text: "Third.", isLive: true)
        log.mirror([fresh])
        #expect(log.lines.map(\.text) == ["First question.", "Second one is still going", "Third."])
        #expect(log.lines[1].isLive == false)
        #expect(log.lines[2].isLive == true)
    }

    @Test func mirrorDropsEmptyRows() {
        var log = TranscriptLog()
        log.mirror([CaptionLine(text: "", isLive: true), CaptionLine(text: "ok", isLive: false)])
        #expect(log.lines.map(\.text) == ["ok"])
    }

    @Test func questionsComeFromTheNewestSentences() {
        var log = TranscriptLog()
        log.append("Tell me about actors. How do they differ from classes?")
        log.append("And when would you pick one?")
        #expect(log.question(sentences: 1) == "And when would you pick one?")
        #expect(log.question(sentences: 2) == "How do they differ from classes? And when would you pick one?")
        #expect(log.question(sentences: 0) == "Tell me about actors. How do they differ from classes? And when would you pick one?")
        #expect(TranscriptLog().question(sentences: 1) == nil)
    }

    @Test func answeringMovesTheWatermarkAndZeroMeansEverythingSince() {
        var log = TranscriptLog()
        log.append("Old question?")
        log.markAnswered()
        #expect(log.pending.isEmpty)
        #expect(log.question(sentences: 0) == nil)
        // The last sentence is still reachable on purpose: the reader can see it in the strip.
        #expect(log.question(sentences: 1) == "Old question?")
        log.append("New one.")
        log.append("And more.")
        #expect(log.pending.map(\.text) == ["New one.", "And more."])
        #expect(log.question(sentences: 0) == "New one. And more.")
    }

    @Test func trimmingKeepsTheWatermarkInStep() {
        var log = TranscriptLog()
        for index in 0..<TranscriptLog.limit { log.append("q \(index)") }
        log.markAnswered()
        log.append("fresh")
        #expect(log.answeredCount == TranscriptLog.limit - 1)
        #expect(log.pending.map(\.text) == ["fresh"])
    }

    @Test func clearForgetsEverything() {
        var log = TranscriptLog()
        log.append("a")
        log.markAnswered()
        log.clear()
        #expect(log.isEmpty)
        #expect(log.answeredCount == 0)
    }

    @Test func answerHotkeysHaveDefaultsThatDoNotCollide() {
        let map = HotkeyCatalog.normalize(nil)
        #expect(map[.answerLastSentence] == "CommandOrControl+num1")
        #expect(map[.answerRecent] == "CommandOrControl+num3")
        #expect(map[.answerAll] == "CommandOrControl+num0")
        for action in [HotkeyAction.answerLastSentence, .answerRecent, .answerAll] {
            #expect(HotkeyCatalog.conflict(for: action, in: map) == nil)
            #expect(HotkeyCatalog.items.contains { $0.id == action && $0.group == .audio })
        }
    }

    @Test func captionsToDraftDefaultsOnAndDecodesOldSettings() throws {
        var settings = PublicSettings.default
        #expect(settings.captionsToDraft == true)
        settings.captionsToDraft = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PublicSettings.self, from: data)
        #expect(decoded.captionsToDraft == false)
        // A settings blob saved before the field existed still decodes.
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["storedCaptionsToDraft"] = nil
        let old = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(PublicSettings.self, from: old).captionsToDraft == true)
    }
}
