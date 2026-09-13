import SwiftUI

/// The tray Cue mark, turned with iPhone scroll physics.
///
/// `flick` is one opening impulse that coasts to rest (empty chat).
/// `busy` keeps a thinking cruise while `spinning` is on, then coasts to rest when it turns off.
struct CueMarkSpin: View {
    enum Style {
        case flick
        case busy
    }

    var pointSize: CGFloat = 18
    var spinning: Bool = false
    var style: Style = .busy

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin = Date()
    @State private var baseAngle = 0.0
    @State private var startVelocity = 0.0
    @State private var cruise = 0.0
    @State private var animating = false
    @State private var coastTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || !animating)) { context in
            let elapsed = reduceMotion ? 0 : max(0, context.date.timeIntervalSince(origin))
            let angle = baseAngle + ScrollMomentum.displacement(
                initialVelocity: startVelocity,
                cruise: cruise,
                at: elapsed
            )
            CueMark(pointSize: pointSize)
                .rotationEffect(.degrees(reduceMotion ? 0 : angle))
        }
        .frame(width: pointSize, height: pointSize)
        .onAppear { engage(spinning) }
        .onChange(of: spinning) { _, on in engage(on) }
        .onDisappear { coastTask?.cancel() }
        .accessibilityHidden(style == .flick)
        .accessibilityLabel(style == .busy ? "Responding" : "Cue")
    }

    private var impulse: Double { style == .flick ? 1080 : 720 }
    private var busyCruise: Double { style == .busy ? 180 : 0 }

    private func engage(_ on: Bool) {
        coastTask?.cancel()
        snapshotClock()
        if reduceMotion {
            startVelocity = 0
            cruise = 0
            animating = false
            return
        }
        if on {
            startVelocity = max(startVelocity, impulse)
            cruise = busyCruise
            animating = true
            if style == .flick {
                scheduleRest(from: startVelocity)
            }
        } else {
            cruise = 0
            animating = startVelocity > 1
            if animating {
                scheduleRest(from: startVelocity)
            }
        }
    }

    private func snapshotClock() {
        let now = Date()
        let elapsed = now.timeIntervalSince(origin)
        baseAngle += ScrollMomentum.displacement(initialVelocity: startVelocity, cruise: cruise, at: elapsed)
        startVelocity = ScrollMomentum.velocity(initialVelocity: startVelocity, cruise: cruise, at: elapsed)
        origin = now
    }

    private func scheduleRest(from velocity: Double) {
        let duration = ScrollMomentum.durationUntil(velocity: 1, initialVelocity: velocity, cruise: 0)
        guard duration.isFinite else { return }
        coastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(min(duration, 16) + 0.05))
            guard !Task.isCancelled else { return }
            snapshotClock()
            startVelocity = 0
            cruise = 0
            animating = false
        }
    }
}
