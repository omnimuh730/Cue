import Foundation

/// What Cue has heard this session, oldest first. The composer draft is one consumer of listen
/// output; this log is the other, and it survives `resetAfterSend` so the reader can see the
/// question they just answered and grab the next one.
///
/// Whisper and Apple Speech feed it one committed line per transcribed segment. The
/// Accessibility source mirrors `CaptionLineAssembler`, whose rows carry stable ids: rows the
/// assembler still has are updated in place (the live row keeps changing), rows it has dropped
/// (after its own reset) stay here as history.
nonisolated struct TranscriptLog: Equatable, Sendable {
    static let limit = 60

    private(set) var lines: [CaptionLine] = []
    /// Lines before this index have already been sent as a question.
    private(set) var answeredCount = 0

    var isEmpty: Bool { lines.isEmpty }

    /// Lines that have not been answered yet.
    var pending: [CaptionLine] {
        Array(lines.dropFirst(min(answeredCount, lines.count)))
    }

    mutating func append(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        lines.append(CaptionLine(text: cleaned, isLive: false))
        trim()
    }

    mutating func mirror(_ snapshot: [CaptionLine]) {
        let ids = Set(snapshot.map(\.id))
        var kept = lines.filter { !ids.contains($0.id) && !$0.text.isEmpty }
        for index in kept.indices { kept[index].isLive = false }
        lines = kept + snapshot.filter { !$0.text.isEmpty }
        trim()
    }

    /// Marks everything heard so far as answered; `pending` starts after it.
    mutating func markAnswered() {
        answeredCount = lines.count
    }

    mutating func clear() {
        lines = []
        answeredCount = 0
    }

    /// The most recent `sentences` sentences (0 = everything not yet answered), as one question.
    func question(sentences: Int) -> String? {
        let source = sentences <= 0 ? pending : lines
        let text = CaptionSentenceGrab.grab(from: source, count: sentences)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private mutating func trim() {
        let overflow = lines.count - Self.limit
        guard overflow > 0 else { return }
        lines.removeFirst(overflow)
        answeredCount = max(0, answeredCount - overflow)
    }
}
