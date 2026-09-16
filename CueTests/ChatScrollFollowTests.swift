import Foundation
import Testing
@testable import Cue

struct ChatScrollFollowTests {
    @Test func startsPinnedToLatest() {
        var follow = ChatScrollFollow()
        #expect(follow.shouldFollow)
        let first = follow.apply(ChatScrollSnapshot(contentHeight: 400, visibleMaxY: 400))
        #expect(first)
        #expect(follow.shouldFollow)
    }

    @Test func scrollingUpUnpins() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_200, visibleMaxY: 1_200))
        let moved = follow.apply(ChatScrollSnapshot(contentHeight: 1_200, visibleMaxY: 700))
        #expect(!moved)
        #expect(!follow.shouldFollow)
    }

    @Test func contentGrowthDoesNotUnpinAndRequestsFollow() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 800, visibleMaxY: 800))
        // Streaming added 240pt below the viewport before the follow-up scroll lands.
        let grew = follow.apply(ChatScrollSnapshot(contentHeight: 1_040, visibleMaxY: 800))
        #expect(grew)
        #expect(follow.shouldFollow)
    }

    @Test func wheelTicksInsideSlackDoNotYank() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 1_000))
        // Still inside the bottom slack; do not snap back or the reader can never leave.
        let nudged = follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 960))
        #expect(!nudged)
        #expect(follow.shouldFollow)
    }

    @Test func scrollingBackToBottomRepins() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_200, visibleMaxY: 1_200))
        follow.apply(ChatScrollSnapshot(contentHeight: 1_200, visibleMaxY: 400))
        #expect(!follow.shouldFollow)
        let returned = follow.apply(ChatScrollSnapshot(contentHeight: 1_200, visibleMaxY: 1_180))
        #expect(!returned)
        #expect(follow.shouldFollow)
    }

    @Test func furtherGrowthStaysUnpinnedUntilReaderReturns() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 1_000))
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 500))
        let grew = follow.apply(ChatScrollSnapshot(contentHeight: 1_400, visibleMaxY: 500))
        let grewAgain = follow.apply(ChatScrollSnapshot(contentHeight: 1_800, visibleMaxY: 500))
        #expect(!grew)
        #expect(!grewAgain)
        #expect(!follow.shouldFollow)
        follow.jumpToLatest()
        #expect(follow.shouldFollow)
    }

    @Test func touchingTheScrollViewSuspendsFollow() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 1_000))
        follow.setInteracting(true)
        // A slow drag moves less per frame than streaming growth does, so geometry alone cannot
        // tell them apart; while the reader is on the scroll view, nothing is pulled from under it.
        let duringDrag = follow.apply(ChatScrollSnapshot(contentHeight: 1_200, visibleMaxY: 1_004))
        #expect(!duringDrag)
        #expect(!follow.shouldFollow)
    }

    @Test func lettingGoAwayFromTheBottomStaysUnpinned() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 1_000))
        follow.setInteracting(true)
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 400))
        let resumed = follow.setInteracting(false)
        #expect(!resumed)
        #expect(!follow.shouldFollow)
        let grew = follow.apply(ChatScrollSnapshot(contentHeight: 1_400, visibleMaxY: 400))
        #expect(!grew)
    }

    @Test func lettingGoAtTheBottomResumesFollow() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 1_000))
        follow.setInteracting(true)
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 300))
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 990))
        let resumed = follow.setInteracting(false)
        #expect(resumed)
        #expect(follow.shouldFollow)
    }

    @Test func smoothGrowthKeepsFollowing() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 1_000, visibleMaxY: 1_000))
        // The streaming reveal adds a point or two a frame; every one of those has to carry the
        // transcript along, or it drifts off the bottom a pixel at a time.
        let nudged = follow.apply(ChatScrollSnapshot(contentHeight: 1_002, visibleMaxY: 1_000))
        #expect(nudged)
        #expect(follow.shouldFollow)
    }

    @Test func layoutJitterDoesNotUnpin() {
        var follow = ChatScrollFollow()
        follow.apply(ChatScrollSnapshot(contentHeight: 900, visibleMaxY: 900))
        let jitter = follow.apply(ChatScrollSnapshot(contentHeight: 900, visibleMaxY: 896))
        #expect(!jitter)
        #expect(follow.shouldFollow)
    }
}
