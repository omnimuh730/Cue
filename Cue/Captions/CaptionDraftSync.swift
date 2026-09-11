import Foundation

/// Maps AirScript’s unbounded caption cache onto a single composer string
/// without stacking live revisions of the same sentence.
nonisolated enum CaptionDraftSync {
    static func text(from lines: [CaptionLine]) -> String {
        CaptionSentenceGrab.orderedSentences(from: lines).joined(separator: " ")
    }

    static func apply(snapshot lines: [CaptionLine], to draft: String, previousSnapshot: String) -> (draft: String, snapshot: String) {
        let next = text(from: lines)
        return (replace(in: draft, previous: previousSnapshot, next: next), next)
    }

    static func replace(in draft: String, previous: String, next: String) -> String {
        if previous.isEmpty {
            if next.isEmpty { return draft }
            if draft.isEmpty { return next }
            return draft + " " + next
        }
        if draft == previous { return next }
        if let range = draft.range(of: previous, options: .backwards) {
            var updated = draft
            updated.replaceSubrange(range, with: next)
            return updated.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if next.isEmpty { return draft }
        return draft + " " + next
    }
}
