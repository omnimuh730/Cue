import Foundation

nonisolated struct CaptionLine: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var isLive: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        isLive: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isLive = isLive
        self.createdAt = createdAt
    }
}
