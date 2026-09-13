import CoreGraphics
import Foundation
import Testing
@testable import Cue

struct HeroMotionTests {
    @Test func flickStartsFastThenDecays() {
        let v0 = 1080.0
        let start = ScrollMomentum.velocity(initialVelocity: v0, at: 0)
        let later = ScrollMomentum.velocity(initialVelocity: v0, at: 0.4)
        let muchLater = ScrollMomentum.velocity(initialVelocity: v0, at: 2)
        #expect(start == v0)
        #expect(later < start)
        #expect(muchLater < later)
        #expect(muchLater > 0)
    }

    @Test func displacementMatchesUIKitFrameSum() {
        let v0 = 600.0
        let time = 0.25
        let rate = ScrollMomentum.fastRate
        let frames = time * ScrollMomentum.framesPerSecond
        let expected = (v0 / 60) * (1 - pow(rate, frames)) / (1 - rate)
        let actual = ScrollMomentum.displacement(initialVelocity: v0, at: time)
        #expect(abs(actual - expected) < 0.0001)
    }

    @Test func zeroTimeHasNoTravel() {
        #expect(ScrollMomentum.displacement(initialVelocity: 1080, at: 0) == 0)
        #expect(ScrollMomentum.displacement(initialVelocity: 1080, at: -1) == 0)
    }

    @Test func letterLandsOnStage() {
        let start = LetterOrbit.pose(0, parity: 0)
        let end = LetterOrbit.pose(1, parity: 0)
        #expect(start.offset != .zero)
        #expect(start.opacity < 0.05)
        #expect(end.offset == .zero)
        #expect(end.rotation == 0)
        #expect(end.opacity == 1)
        #expect(end.blur == 0)
        #expect(end.scale == 1)
    }

    @Test func cruiseHoldsAFloor() {
        let cruise = 180.0
        let later = ScrollMomentum.velocity(initialVelocity: 720, cruise: cruise, at: 12)
        #expect(abs(later - cruise) < 1)
        let travel = ScrollMomentum.displacement(initialVelocity: 720, cruise: cruise, at: 2)
        #expect(travel > cruise * 2)
    }

    @Test func restTimeIsFiniteWithoutCruise() {
        let duration = ScrollMomentum.durationUntil(velocity: 1, initialVelocity: 1080)
        #expect(duration.isFinite)
        #expect(duration > 1)
        #expect(ScrollMomentum.durationUntil(velocity: 1, initialVelocity: 720, cruise: 180).isInfinite)
    }

    @Test func neighborsOrbitFromOppositeSides() {
        let a = LetterOrbit.pose(0, parity: 0)
        let b = LetterOrbit.pose(0, parity: 1)
        #expect(a.offset.width * b.offset.width < 0)
    }
}
