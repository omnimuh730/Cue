import SwiftUI

/// Cue's orb: a translucent sphere of drifting pastel light, sitting in its own glow.
///
/// At full `energy` the light flows quickly, which is how Cue shows it is working: the thinking
/// row, the streaming tail, the sidebar's busy chats. The color field is a Metal shader; the
/// sphere — specular, shadow, rim, halo — is native gradients and masks on top of it. It runs
/// at 30 fps, only while the panel is on screen, and small orbs use a gradient halo rather than
/// a blur so a row of busy chats stays cheap.
struct CueOrb: View {
    var size: CGFloat
    /// 0 idle, 1 working.
    var energy: Double = 0
    /// Viewing angle in −1…1 per axis; shifts the light for a parallax under the pointer.
    var tilt: CGPoint = .zero
    /// Read out by VoiceOver when set; the orb is decoration otherwise.
    var label: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cueMotionActive) private var motionActive

    private var paused: Bool { reduceMotion || !motionActive }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let time = paused ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let breath = paused ? 1 : 1 + 0.018 * sin(time * (1.1 + energy * 2))
            ZStack {
                halo(time)
                aurora(time)
                    .overlay { sphere }
                    .clipShape(Circle())
            }
            .scaleEffect(breath)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    /// The glow the sphere sits in. Above 40 pt it is the light itself, blurred; below, a radial
    /// gradient in the same tint, which reads the same at that size for a fraction of the cost.
    @ViewBuilder
    private func halo(_ time: TimeInterval) -> some View {
        if size >= 40 {
            aurora(time)
                .scaleEffect(1.3)
                .blur(radius: size * 0.16)
                .opacity(0.45 + 0.3 * energy)
        } else {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.75, green: 0.6, blue: 1).opacity(0.5 + 0.25 * energy), .clear],
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.75
                    )
                )
                .scaleEffect(1.5)
        }
    }

    private func aurora(_ time: TimeInterval) -> some View {
        Circle()
            .fill(.white)
            .colorEffect(
                ShaderLibrary.cueAurora(
                    .boundingRect,
                    .float(Float(time)),
                    .float2(Float(tilt.x), Float(tilt.y)),
                    .float(Float(energy)),
                    .float(1)
                )
            )
    }

    /// Specular at the upper left, a soft shadow toward the rim, and a hairline of glass: the
    /// native pass that turns a disc of color into a sphere.
    private var sphere: some View {
        ZStack {
            RadialGradient(
                colors: [.white.opacity(0.78), .white.opacity(0)],
                center: UnitPoint(x: 0.32 + tilt.x * 0.08, y: 0.26 + tilt.y * 0.08),
                startRadius: 0,
                endRadius: size * 0.42
            )
            RadialGradient(
                colors: [.clear, .black.opacity(0.12)],
                center: .center,
                startRadius: size * 0.3,
                endRadius: size * 0.55
            )
            Circle().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.9), .white.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.5, size * 0.012)
            )
        }
    }
}

/// A ring of aurora light around a glass shape while `active`: Cue's version of the edge glow
/// that says an assistant is working. One shader pass — the glow is a distance field, not a
/// blur — at 30 fps, only while the panel is on screen. Fades in and out on the panel spring.
struct CueAuroraGlowModifier: ViewModifier {
    var active: Bool
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cueMotionActive) private var motionActive

    /// How far past the glass edge the glow reaches.
    private static let spill: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    ring
                        .transition(.opacity)
                }
            }
            .animation(CueMotion.panel, value: active)
    }

    /// The canvas is the glass plus `spill` on every side, so the glow can reach past the edge.
    private var ring: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !motionActive)) { context in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                Rectangle()
                    .fill(.white)
                    .frame(width: geo.size.width + Self.spill * 2, height: geo.size.height + Self.spill * 2)
                    .colorEffect(
                        ShaderLibrary.cueAuroraRing(
                            .boundingRect,
                            .float(Float(time)),
                            .float(Float(cornerRadius)),
                            .float(Float(Self.spill)),
                            .float(9)
                        )
                    )
                    .offset(x: -Self.spill, y: -Self.spill)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func cueAuroraGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        modifier(CueAuroraGlowModifier(active: active, cornerRadius: cornerRadius))
    }
}
