import CoreGraphics
import Foundation

/// UIKit `UIScrollView` flick physics. Velocity decays by `rate` every 1/60s, which is
/// the curve of iPhone list scrolling: fast at the flick, then a long gravity-like ease.
enum ScrollMomentum {
    /// `UIScrollViewDecelerationRateNormal`
    static let normalRate = 0.998
    /// `UIScrollViewDecelerationRateFast`
    static let fastRate = 0.99
    static let framesPerSecond = 60.0

    /// Instantaneous velocity after `time` seconds, same units as `initialVelocity`.
    /// A non-zero `cruise` is the floor a busy spinner holds instead of stalling.
    static func velocity(rate: Double = fastRate, initialVelocity: Double, cruise: Double = 0, at time: TimeInterval) -> Double {
        cruise + (initialVelocity - cruise) * pow(rate, max(0, time) * framesPerSecond)
    }

    /// Degrees (or points) travelled after `time` seconds from a flick of `initialVelocity` per second.
    static func displacement(rate: Double = fastRate, initialVelocity: Double, cruise: Double = 0, at time: TimeInterval) -> Double {
        let t = max(0, time)
        return cruise * t + restDisplacement(rate: rate, initialVelocity: initialVelocity - cruise, at: t)
    }

    /// Seconds until velocity falls to `threshold`. Infinite if a cruise holds it up.
    static func durationUntil(velocity threshold: Double, rate: Double = fastRate, initialVelocity: Double, cruise: Double = 0) -> TimeInterval {
        let excess = initialVelocity - cruise
        let target = threshold - cruise
        guard excess > 0, target > 0, target < excess, rate > 0, rate < 1 else {
            return excess <= max(0, target) ? 0 : .infinity
        }
        return log(target / excess) / (framesPerSecond * log(rate))
    }

    private static func restDisplacement(rate: Double, initialVelocity: Double, at time: TimeInterval) -> Double {
        let frames = max(0, time) * framesPerSecond
        let perFrame = initialVelocity / framesPerSecond
        let decay = 1 - rate
        guard decay > 0 else { return initialVelocity * max(0, time) }
        return perFrame * (1 - pow(rate, frames)) / decay
    }
}

/// Spiral path a glyph takes from offstage onto its rest slot.
enum LetterOrbit {
    static func pose(_ progress: CGFloat, parity: Int) -> Pose {
        let p: CGFloat = min(max(progress, 0), 1)
        let remaining: CGFloat = 1 - p
        let side: CGFloat = parity.isMultiple(of: 2) ? 1 : -1
        let sweep: CGFloat = .pi * 1.2 * remaining
        let radius: CGFloat = 36 * remaining
        let x: CGFloat = sin(sweep) * radius * side
        let y: CGFloat = (1 - cos(sweep)) * radius * 0.9 + remaining * 6
        let rotation = Double(remaining * 52 * side)
        let opacity = Double(min(1, p * 1.4))
        return Pose(
            offset: CGSize(width: x, height: y),
            rotation: rotation,
            opacity: opacity,
            blur: remaining * 8,
            scale: 0.42 + 0.58 * p
        )
    }

    struct Pose: Equatable {
        var offset: CGSize
        var rotation: Double
        var opacity: Double
        var blur: CGFloat
        var scale: CGFloat
    }
}
