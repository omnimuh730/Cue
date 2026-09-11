import Foundation

/// Ports LastCry’s rolling-caption merge (`checkNewLine` + pop/replace).
/// A new crop replaces the live chunk when it is the same utterance grown or
/// lightly revised — punctuation and small token edits do not start a row.
nonisolated enum CaptionTextMerge {
    static func collapse(_ parts: [String]) -> [String] {
        var collapsed: [String] = []
        for part in parts where !isChrome(part) {
            if let index = collapsed.lastIndex(where: { isSameUtterance($0, part) }) {
                collapsed[index] = preferred(collapsed[index], part)
                var later = collapsed.count - 1
                while later > index {
                    if isSameUtterance(collapsed[later], part) {
                        collapsed.remove(at: later)
                    }
                    later -= 1
                }
            } else {
                collapsed.append(part)
            }
        }
        return collapsed
    }

    static func isChrome(_ line: String) -> Bool {
        let folded = line
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = folded.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        switch stripped {
        case "live caption", "live captions",
             "live caption running", "live captions running",
             "microphone off", "microphone on",
             "mic off", "mic on":
            return true
        default:
            return false
        }
    }

    /// LastCry keeps the latest crop of the same caption window.
    static func preferred(_ older: String, _ newer: String) -> String {
        if newer.count >= older.count { return newer }
        let olderFolded = folded(older)
        let newerFolded = folded(newer)
        if olderFolded.hasPrefix(newerFolded) { return older }
        return newer
    }

    /// True when `newer` is the same spoken line as `older`, grown or revised.
    static func isSameUtterance(_ older: String, _ newer: String) -> Bool {
        if older == newer { return true }
        if newer.hasPrefix(older) || older.hasPrefix(newer) { return true }

        let olderFolded = folded(older)
        let newerFolded = folded(newer)
        if olderFolded.isEmpty || newerFolded.isEmpty { return false }
        if olderFolded == newerFolded { return true }
        if newerFolded.hasPrefix(olderFolded) || olderFolded.hasPrefix(newerFolded) { return true }

        let olderWords = words(older)
        let newerWords = words(newer)
        let shortCount = min(olderWords.count, newerWords.count)
        guard shortCount > 0 else { return false }

        let short = olderWords.count <= newerWords.count ? olderWords : newerWords
        let long = olderWords.count <= newerWords.count ? newerWords : olderWords
        if shortCount < 4 {
            return long.starts(with: short)
        }

        let coverage = Double(longestCommonSubsequence(olderWords, newerWords)) / Double(shortCount)
        if coverage >= 0.75 { return true }

        return alignedPrefix(short, long)
    }

    /// Words in `prev` that have scrolled off before the overlap with `current`.
    static func scrolledOffPrefix(prev: String, current: String) -> String? {
        if isSameUtterance(prev, current) { return nil }

        let raw = prev.split(whereSeparator: \.isWhitespace).map(String.init)
        let prevWords = words(prev)
        let currentWords = words(current)
        var overlap = min(prevWords.count, currentWords.count)
        while overlap > 0 {
            if Array(prevWords.suffix(overlap)) == Array(currentWords.prefix(overlap)) {
                break
            }
            overlap -= 1
        }
        guard overlap >= 4, overlap < prevWords.count else { return nil }

        let stable: [String]
        if raw.count == prevWords.count {
            stable = Array(raw.dropLast(overlap))
        } else {
            stable = Array(prevWords.dropLast(overlap))
        }
        let text = stable.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func folded(_ text: String) -> String {
        words(text).joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func alignedPrefix(_ short: [String], _ long: [String]) -> Bool {
        let allowed = max(1, short.count / 4)
        var mismatches = 0
        var longIndex = 0
        for token in short {
            if longIndex >= long.count { return false }
            if token == long[longIndex] {
                longIndex += 1
                continue
            }
            if longIndex + 1 < long.count, token == long[longIndex + 1] {
                longIndex += 2
                mismatches += 1
            } else {
                mismatches += 1
                longIndex += 1
            }
            if mismatches > allowed { return false }
        }
        return true
    }

    private static func longestCommonSubsequence(_ left: [String], _ right: [String]) -> Int {
        if left.isEmpty || right.isEmpty { return 0 }
        var previous = Array(repeating: 0, count: right.count + 1)
        var current = Array(repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            for j in 1...right.count {
                if left[i - 1] == right[j - 1] {
                    current[j] = previous[j - 1] + 1
                } else {
                    current[j] = max(previous[j], current[j - 1])
                }
            }
            swap(&previous, &current)
            current = Array(repeating: 0, count: right.count + 1)
        }
        return previous[right.count]
    }
}
