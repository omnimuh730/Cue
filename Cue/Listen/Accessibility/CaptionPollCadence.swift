import Foundation

nonisolated struct CaptionPollCadence: Equatable, Sendable {
    static let speaking: TimeInterval = 0.1
    static let pollsBeforeBackoff = 3
    static let idleRungs: [TimeInterval] = [0.25, 0.5, 1.0]
    static let fullWalkEveryActivePolls = 5

    var interval: TimeInterval = Self.speaking
    private var unchangedAtInterval = 0

    var isSpeaking: Bool { interval <= Self.speaking + 0.001 }

    mutating func noteChange() {
        interval = Self.speaking
        unchangedAtInterval = 0
    }

    mutating func noteUnchanged() {
        unchangedAtInterval += 1
        guard unchangedAtInterval >= Self.pollsBeforeBackoff else { return }
        unchangedAtInterval = 0
        interval = Self.nextIdle(after: interval)
    }

    mutating func resetToSpeaking() {
        noteChange()
    }

    static func nextIdle(after current: TimeInterval) -> TimeInterval {
        for rung in idleRungs where current < rung - 0.001 {
            return rung
        }
        return idleRungs.last ?? 1.0
    }
}
