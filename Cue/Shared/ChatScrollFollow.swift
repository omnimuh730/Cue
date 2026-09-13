import CoreGraphics
import Foundation

/// Snapshot of a chat `ScrollView` used to decide whether new tokens should follow the bottom.
struct ChatScrollSnapshot: Equatable {
    var contentHeight: CGFloat
    var visibleMaxY: CGFloat
}

/// Pins the transcript to the latest message only while the reader is already at the bottom.
///
/// Content growth during streaming must not count as “the user scrolled away,” or the view
/// unpins itself and then `scrollTo` yanks it back. A drop in `visibleMaxY` is a real scroll up.
/// Auto-follow runs only when content grows, so a scroll-up can leave the bottom slack without
/// being corrected on every wheel tick.
struct ChatScrollFollow: Equatable {
    /// How close to the end of the content counts as “at the bottom.”
    static let bottomSlack: CGFloat = 80
    /// Ignore sub-point layout jitter so LazyVStack recycling does not unpin.
    static let moveThreshold: CGFloat = 8

    var pinnedToBottom = true
    var lastContentHeight: CGFloat = 0
    var lastVisibleMaxY: CGFloat = 0

    var shouldFollow: Bool { pinnedToBottom }

    /// Updates pin state. Returns `true` when the transcript should snap to the latest message.
    @discardableResult
    mutating func apply(_ snapshot: ChatScrollSnapshot) -> Bool {
        let atBottom = snapshot.contentHeight - snapshot.visibleMaxY <= Self.bottomSlack
        let scrolledUp = snapshot.visibleMaxY < lastVisibleMaxY - Self.moveThreshold
        let contentGrew = snapshot.contentHeight > lastContentHeight + Self.moveThreshold
        if atBottom {
            pinnedToBottom = true
        } else if scrolledUp {
            pinnedToBottom = false
        }
        let shouldScroll = pinnedToBottom && contentGrew
        lastContentHeight = snapshot.contentHeight
        lastVisibleMaxY = snapshot.visibleMaxY
        return shouldScroll
    }

    /// A new user send, or switching conversations, should show the latest turn.
    mutating func jumpToLatest() {
        pinnedToBottom = true
    }
}
