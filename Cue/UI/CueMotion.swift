import SwiftUI

/// Cue's motion vocabulary. A handful of springs shared by every surface so the app moves as one
/// thing: panels settle, controls answer the pointer, and nothing lingers past its use.
enum CueMotion {
    /// Panels sliding in and out: the sidebar, pickers, dialogs.
    static let panel = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Small controls answering hover or press.
    static let control = Animation.spring(response: 0.26, dampingFraction: 0.72)
    /// A message arriving in the transcript.
    static let arrive = Animation.spring(response: 0.48, dampingFraction: 0.84)
    /// Quick opacity changes.
    static let fade = Animation.easeOut(duration: 0.16)
}

// MARK: - Motion gate

/// Whether continuous motion should run at all: the panel is on screen and Reduce Motion is
/// off. Set once at the root; every orb, glow, shimmer, and particle field reads it, so a hidden
/// or covered Cue draws nothing and costs nothing.
struct CueMotionActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var cueMotionActive: Bool {
        get { self[CueMotionActiveKey.self] }
        set { self[CueMotionActiveKey.self] = newValue }
    }
}

/// Compiles the effect shaders once, off the main thread, so the first orb or sweep on screen
/// does not stall a frame on pipeline creation.
enum CueShaderWarmup {
    static func run() {
        Task.detached(priority: .utility) {
            let shaders: [Shader] = [
                ShaderLibrary.cueAurora(.boundingRect, .float(0), .float2(0, 0), .float(0), .float(1)),
                ShaderLibrary.cueAuroraRing(.boundingRect, .float(0), .float(0), .float(0), .float(1)),
                ShaderLibrary.cueShimmer(.boundingRect, .float(0), .float(0)),
                ShaderLibrary.cueSparkle(.boundingRect, .float(0), .float(0))
            ]
            for shader in shaders {
                try? await shader.compile(as: .colorEffect)
            }
        }
    }
}

// MARK: - Light sweep (Metal)

/// A band of light crossing the view while `active`; the resting state is the plain view.
struct CueShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cueMotionActive) private var motionActive
    var active: Bool
    var period: TimeInterval
    var strength: Double

    func body(content: Content) -> some View {
        if active, motionActive, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let progress = t.truncatingRemainder(dividingBy: period) / period
                content.colorEffect(
                    ShaderLibrary.cueShimmer(.boundingRect, .float(Float(progress)), .float(Float(strength)))
                )
            }
        } else {
            content
        }
    }
}

// MARK: - Sparkle burst (Metal)

/// Glints that twinkle inside the view for `duration` seconds each time `trigger` changes, then
/// fade out and cost nothing until the next change.
struct CueSparkleBurstModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var trigger: Trigger
    var duration: TimeInterval
    var strength: Double

    @Environment(\.cueMotionActive) private var motionActive
    @State private var burstStart: Date?

    func body(content: Content) -> some View {
        Group {
            if let burstStart, motionActive, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let elapsed = context.date.timeIntervalSince(burstStart)
                    let envelope = max(0, 1 - elapsed / duration)
                    content.colorEffect(
                        ShaderLibrary.cueSparkle(
                            .boundingRect,
                            .float(Float(elapsed)),
                            .float(Float(strength * envelope * envelope))
                        )
                    )
                    .onChange(of: elapsed >= duration) { _, done in
                        if done { self.burstStart = nil }
                    }
                }
            } else {
                content
            }
        }
        .onChange(of: trigger) { _, _ in
            burstStart = Date()
        }
    }
}

// MARK: - Native motion helpers

/// Press feedback for plain buttons: a quick spring dip, no color change.
struct CuePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(CueMotion.control, value: configuration.isPressed)
    }
}

/// Lifts a control slightly toward the pointer while hovered.
struct CueHoverLiftModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? scale : 1)
            .animation(CueMotion.control, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Tracks the pointer over a view as a tilt in −1…1 on each axis, centred on the view. Off the
/// view it eases back to level.
struct CuePointerTiltModifier: ViewModifier {
    @Binding var tilt: CGPoint
    var damping: CGFloat

    func body(content: Content) -> some View {
        content.onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let size = tiltSize
                guard size.width > 0, size.height > 0 else { return }
                let next = CGPoint(
                    x: ((point.x / size.width) * 2 - 1) * damping,
                    y: ((point.y / size.height) * 2 - 1) * damping
                )
                withAnimation(CueMotion.control) { tilt = next }
            case .ended:
                withAnimation(CueMotion.panel) { tilt = .zero }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tiltSize = $0 }
    }

    @State private var tiltSize: CGSize = .zero
}

extension View {
    func cueShimmer(active: Bool, period: TimeInterval = 1.7, strength: Double = 0.5) -> some View {
        modifier(CueShimmerModifier(active: active, period: period, strength: strength))
    }

    func cueSparkleBurst<Trigger: Equatable>(on trigger: Trigger, duration: TimeInterval = 1.1, strength: Double = 0.9) -> some View {
        modifier(CueSparkleBurstModifier(trigger: trigger, duration: duration, strength: strength))
    }

    func cueHoverLift(_ scale: CGFloat = 1.06) -> some View {
        modifier(CueHoverLiftModifier(scale: scale))
    }

    func cuePointerTilt(_ tilt: Binding<CGPoint>, damping: CGFloat = 1) -> some View {
        modifier(CuePointerTiltModifier(tilt: tilt, damping: damping))
    }
}
