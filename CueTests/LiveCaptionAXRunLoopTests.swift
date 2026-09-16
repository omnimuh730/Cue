import Foundation
import Testing
@testable import Cue

/// The AX thread hop that listen start/stop goes through. Toggling listen twice used to trap the
/// process here, so these exercise exactly that sequence.
struct LiveCaptionAXRunLoopTests {
    @Test func syncHopRunsOnTheAXThreadAndReturns() {
        let loop = LiveCaptionAXRunLoop()
        loop.start()
        defer { loop.stop() }
        let onThread = loop.performSync { loop.isOnAXThread }
        #expect(onThread)
        #expect(loop.performSync { 41 + 1 } == 42)
    }

    @Test func repeatedStartStopCyclesSurviveSyncTeardown() {
        let loop = LiveCaptionAXRunLoop()
        for _ in 0..<20 {
            loop.start()
            // Same shape as `LiveCaptionAXClient.stop()`: a sync hop, then the loop goes down.
            loop.performSync { Thread.sleep(forTimeInterval: 0.001) }
            loop.stop()
        }
        #expect(loop.cfRunLoop == nil)
    }

    @Test func syncHopWithoutALoopRunsInline() {
        let loop = LiveCaptionAXRunLoop()
        #expect(loop.performSync { "inline" } == "inline")
    }
}
