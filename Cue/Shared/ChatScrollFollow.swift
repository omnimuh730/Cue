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
///
/// Geometry alone cannot tell a slow drag apart from streaming growth — both move `visibleMaxY`
/// by a few points a frame — so while the scroll view reports the reader is touching it, follow
/// is suspended outright and the pin is re-decided from where they let go.
struct ChatScrollFollow: Equatable {
    /// How close to the end of the content counts as “at the bottom.”
    static let bottomSlack: CGFloat = 80
    /// Ignore sub-point layout jitter so LazyVStack recycling does not unpin.
    static let moveThreshold: CGFloat = 8
    /// Any real growth should carry the transcript along; the streaming reveal adds a point or
    /// two per frame, and a threshold coarse enough to ignore that would stop following.
    static let growthThreshold: CGFloat = 0.5

    var pinnedToBottom = true
    /// True while the reader has hold of the scroll view (drag, wheel, or momentum).
    private(set) var interacting = false
    private var lastContentHeight: CGFloat = 0
    private var lastVisibleMaxY: CGFloat = 0

    var shouldFollow: Bool { pinnedToBottom && !interacting }

    /// Updates pin state. Returns `true` when the transcript should snap to the latest message.
    @discardableResult
    mutating func apply(_ snapshot: ChatScrollSnapshot) -> Bool {
        let atBottom = snapshot.contentHeight - snapshot.visibleMaxY <= Self.bottomSlack
        let scrolledUp = snapshot.visibleMaxY < lastVisibleMaxY - Self.moveThreshold
        let contentGrew = snapshot.contentHeight > lastContentHeight + Self.growthThreshold
        lastContentHeight = snapshot.contentHeight
        lastVisibleMaxY = snapshot.visibleMaxY
        if interacting {
            // Never move the content out from under a hand that is on it; just remember whether
            // they are leaving it at the bottom.
            pinnedToBottom = atBottom
            return false
        }
        if atBottom {
            pinnedToBottom = true
        } else if scrolledUp {
            pinnedToBottom = false
        }
        return pinnedToBottom && contentGrew
    }

    /// Reports whether the reader is driving the scroll view. Returns `true` when letting go
    /// leaves the transcript pinned, so the caller can catch up to the latest message.
    @discardableResult
    mutating func setInteracting(_ value: Bool) -> Bool {
        guard interacting != value else { return false }
        interacting = value
        return !value && pinnedToBottom
    }

    /// A new user send, or switching conversations, should show the latest turn.
    mutating func jumpToLatest() {
        pinnedToBottom = true
        interacting = false
    }
}
