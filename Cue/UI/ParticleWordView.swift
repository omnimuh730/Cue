import AppKit
import SpriteKit
import SwiftUI

/// The empty chat's hero: a word written in a couple of thousand star particles.
///
/// The particles blow in like leaves on a wind that crosses the word left to right — each on
/// its own curved, eased path — and settle into the glyphs. They never quite hold still: each
/// drifts on its own small loop around its home while a slow wave runs along the word, so the
/// shape lives without breaking. The pointer is a magnet with the wrong pole: a soft field with
/// no visible edge that eases them aside and lets them slide around it; springs bring them back.
/// SpriteKit draws the sprites; the physics is a few lines per particle per frame. It runs at
/// 60 fps only while the pointer is in the field, 30 otherwise, and not at all while the panel
/// is off screen or Reduce Motion is on (the word is simply there, formed).
struct ParticleWordView: View {
    var word: String = "CUE"

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cueMotionActive) private var motionActive
    @State private var scene = ParticleWordScene()
    @State private var pointerInside = false

    private var paused: Bool { reduceMotion || !motionActive }

    var body: some View {
        SpriteView(
            scene: scene,
            isPaused: paused,
            preferredFramesPerSecond: pointerInside ? 60 : 30,
            options: [.allowsTransparency]
        )
        // Geometric tracking, like `HoverRegion`: the pointer is reported while it crosses the
        // SpriteKit view, which SwiftUI's own hover would treat as leaving.
        .background {
            PointerRegion { point in
                pointerInside = point != nil
                scene.setPointer(point)
            }
        }
        .onAppear {
            scene.configure(word: word, dark: colorScheme == .dark, settled: reduceMotion)
        }
        .onChange(of: colorScheme) { _, scheme in scene.apply(dark: scheme == .dark) }
        .allowsHitTesting(false)
        .accessibilityLabel(word)
    }
}

final class ParticleWordScene: SKScene {
    /// Everything a star needs; the sprite it drives lives in `nodes` at the same index.
    private struct Star {
        var home: CGPoint
        var position: CGPoint
        var velocity: CGPoint = .zero
        /// The small loop it drifts on around home.
        var orbit: CGFloat
        var rate: CGFloat
        var phase: CGFloat
        /// Brightness flicker.
        var twinkle: CGFloat
        var alpha: CGFloat
        var bright: Bool
        /// The way in: where it blows in from, when it sets off, how long it takes, and how far
        /// its path bows sideways. `landed` hands it over to the springs.
        var origin: CGPoint
        var delay: CGFloat
        var duration: CGFloat
        var bow: CGFloat
        var landed: Bool
    }

    /// The word is laid out for this canvas and scaled down to fit a narrower one.
    private static let designSize = CGSize(width: 640, height: 300)
    private static let stiffness: CGFloat = 22
    private static let damping: CGFloat = 6
    /// The magnet: a Gaussian field of this width, no edge.
    private static let fieldSigma: CGFloat = 46
    private static let fieldStrength: CGFloat = 1500

    private let layer = SKNode()
    private var stars: [Star] = []
    private var nodes: [SKSpriteNode] = []
    /// Where the pointer is, and the smoothed point the field is actually centered on.
    private var pointer: CGPoint?
    private var field: CGPoint?
    private var fieldWeight: CGFloat = 0
    private var lastTime: TimeInterval?
    private var startTime: TimeInterval?
    private var dark = true
    private var configured = false

    override init() {
        super.init(size: Self.designSize)
        // Fill the view: `aspectFit` would letterbox, and SpriteKit paints letterbox bars black
        // whatever the background. The star layer scales itself instead.
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        fitLayer()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        fitLayer()
    }

    private func fitLayer() {
        let scale = min(size.width / Self.designSize.width, size.height / Self.designSize.height, 1)
        layer.setScale(max(scale, 0.2))
    }

    /// Lays the word out once. `settled` puts every star at home from the first frame instead
    /// of flying it in.
    func configure(word: String, dark: Bool, settled: Bool) {
        guard !configured else { return }
        configured = true
        self.dark = dark
        let homes = Self.sample(word: word, target: 1900)
        let minX = homes.map(\.x).min() ?? 0
        let maxX = homes.map(\.x).max() ?? 1
        let span = max(maxX - minX, 1)
        var generator = SystemRandomNumberGenerator()
        stars.reserveCapacity(homes.count)
        nodes.reserveCapacity(homes.count)
        for home in homes {
            let bright = CGFloat.random(in: 0..<1, using: &generator) < 0.07
            // Blown in from off to the left and a little above or below, each from its own
            // distance, and the wind reaches the right side of the word last.
            let reach = CGFloat.random(in: 160...420, using: &generator)
            let lift = CGFloat.random(in: -120...120, using: &generator)
            let origin = CGPoint(x: home.x - reach, y: home.y + lift)
            let progressAcross = (home.x - minX) / span
            let star = Star(
                home: home,
                position: settled ? home : origin,
                orbit: bright ? .random(in: 0.6...1.4, using: &generator) : .random(in: 1.0...2.6, using: &generator),
                rate: .random(in: 0.35...1.1, using: &generator),
                phase: .random(in: 0..<(2 * .pi), using: &generator),
                twinkle: .random(in: 0..<(2 * .pi), using: &generator),
                alpha: bright ? .random(in: 0.85...1, using: &generator) : .random(in: 0.5...0.95, using: &generator),
                bright: bright,
                origin: origin,
                delay: 0.15 + progressAcross * 1.1 + .random(in: 0...0.45, using: &generator),
                duration: .random(in: 1.7...2.6, using: &generator),
                bow: .random(in: -70...70, using: &generator),
                landed: settled
            )
            stars.append(star)

            let node = SKSpriteNode(texture: bright ? Self.flareTexture : Self.softTexture)
            let side: CGFloat = bright
                ? .random(in: 7...11, using: &generator)
                : .random(in: 1.8...3.4, using: &generator)
            node.size = CGSize(width: side, height: side)
            node.position = star.position
            node.alpha = settled ? star.alpha : 0
            node.colorBlendFactor = 1
            node.zPosition = bright ? 2 : 1
            if bright {
                // A halo under each bright star; it inherits the color and rides along.
                let halo = SKSpriteNode(texture: Self.softTexture)
                halo.size = CGSize(width: side * 3, height: side * 3)
                halo.colorBlendFactor = 1
                halo.zPosition = -1
                node.addChild(halo)
            }
            nodes.append(node)
            layer.addChild(node)
        }
        apply(dark: dark)
    }

    /// Recolors for the appearance. Additive white light disappears on light glass, so light
    /// mode uses saturated tints with normal blending instead.
    func apply(dark: Bool) {
        self.dark = dark
        let palette = dark ? Palette.dark : Palette.light
        let blend: SKBlendMode = dark ? .add : .alpha
        var generator = SystemRandomNumberGenerator()
        for (index, node) in nodes.enumerated() {
            let color = palette.pick(bright: stars[index].bright, using: &generator)
            node.color = color
            node.blendMode = blend
            for case let halo as SKSpriteNode in node.children {
                halo.color = color
                halo.blendMode = blend
                // Additive halos glow; alpha-blended ones would just be blobs, so they stay faint.
                halo.alpha = dark ? 0.3 : 0.1
            }
        }
    }

    /// Pointer in the hosting view's top-left coordinates, or nil when it has left.
    func setPointer(_ point: CGPoint?) {
        guard let point, let view else {
            pointer = nil
            return
        }
        let viewPoint = CGPoint(x: point.x, y: view.bounds.height - point.y)
        pointer = layer.convert(convertPoint(fromView: viewPoint), from: self)
    }

    override func update(_ currentTime: TimeInterval) {
        guard !stars.isEmpty else { return }
        let dt = CGFloat(min(1.0 / 30.0, lastTime.map { currentTime - $0 } ?? 1.0 / 60.0))
        lastTime = currentTime
        if startTime == nil { startTime = currentTime }
        let t = CGFloat(currentTime.truncatingRemainder(dividingBy: 3600))
        let sinceStart = CGFloat(currentTime - (startTime ?? currentTime))
        stepField(dt)
        let sigma2 = 2 * Self.fieldSigma * Self.fieldSigma

        for index in stars.indices {
            var star = stars[index]
            let node = nodes[index]
            let flicker = 0.78 + 0.22 * sin(t * 2.3 + star.twinkle)

            if !star.landed {
                // On the wind: an eased glide from origin to home that bows sideways on the way,
                // with a little turbulence that dies out as it lands.
                let p = min(max((sinceStart - star.delay) / star.duration, 0), 1)
                let eased = 1 - pow(1 - p, 3)
                let along = CGPoint(
                    x: star.origin.x + (star.home.x - star.origin.x) * eased,
                    y: star.origin.y + (star.home.y - star.origin.y) * eased
                )
                let lateral = sin(p * .pi) * star.bow
                let gust = sin(t * 1.7 + star.phase) * 6 * (1 - eased)
                star.position = CGPoint(x: along.x + gust * 0.6, y: along.y + lateral + gust)
                node.position = star.position
                node.alpha = star.alpha * flicker * min(p * 4, 1)
                if p >= 1 { star.landed = true }
                stars[index] = star
                continue
            }

            // Where home is right now: its own loop, plus the wave passing along the word.
            let wave = sin(t * 0.8 + star.home.x * 0.016) * 2.0
            let targetX = star.home.x + cos(t * star.rate + star.phase) * star.orbit
            let targetY = star.home.y + sin(t * star.rate * 1.3 + star.phase) * star.orbit + wave
            var ax = (targetX - star.position.x) * Self.stiffness - star.velocity.x * Self.damping
            var ay = (targetY - star.position.y) * Self.stiffness - star.velocity.y * Self.damping
            if let field, fieldWeight > 0.001 {
                let dx = star.position.x - field.x
                let dy = star.position.y - field.y
                let d2 = dx * dx + dy * dy
                let d = max(sqrt(d2), 1)
                // Like pole to like pole: strongest at the center, gone by a few sigma, and with
                // a sideways component so stars slide around the pointer instead of only away.
                let f = Self.fieldStrength * fieldWeight * exp(-d2 / sigma2) / d
                ax += dx * f - dy * f * 0.35
                ay += dy * f + dx * f * 0.35
            }
            star.velocity.x += ax * dt
            star.velocity.y += ay * dt
            star.position.x += star.velocity.x * dt
            star.position.y += star.velocity.y * dt
            stars[index] = star

            node.position = star.position
            node.alpha = star.alpha * flicker
        }
    }

    /// The field trails the pointer and fades in and out, so a fast mouse never slams the stars
    /// and leaving the canvas releases them gently.
    private func stepField(_ dt: CGFloat) {
        let ease = min(dt * 9, 1)
        if let pointer {
            if let current = field {
                field = CGPoint(x: current.x + (pointer.x - current.x) * ease, y: current.y + (pointer.y - current.y) * ease)
            } else {
                field = pointer
            }
            fieldWeight += (1 - fieldWeight) * min(dt * 5, 1)
        } else {
            fieldWeight -= fieldWeight * min(dt * 4, 1)
            if fieldWeight < 0.01 { field = nil }
        }
    }

    // MARK: - Layout

    /// Home positions: the word rasterized in a heavy rounded face, then jitter-sampled on a
    /// grid sized so about `target` points land inside the glyphs. Scene coordinates, centered.
    private static func sample(word: String, target: Int) -> [CGPoint] {
        let base = NSFont.systemFont(ofSize: 172, weight: .heavy)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 172) ?? base
        let text = NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: NSColor.white, .kern: 8])
        let bounds = text.size()
        let width = Int(bounds.width.rounded(.up)) + 8
        let height = Int(bounds.height.rounded(.up)) + 8
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
              ),
              let data = context.data else { return [] }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: CGPoint(x: 4, y: 4))
        NSGraphicsContext.restoreGraphicsState()

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var filled = 0
        for index in 0..<(width * height) where pixels[index] > 127 { filled += 1 }
        guard filled > 0 else { return [] }
        let step = max(2.0, (Double(filled) / Double(target)).squareRoot())

        var points: [CGPoint] = []
        points.reserveCapacity(target + target / 8)
        var generator = SystemRandomNumberGenerator()
        var y = 0.0
        while y < Double(height) {
            var x = 0.0
            while x < Double(width) {
                let sx = x + Double.random(in: 0..<step, using: &generator)
                let sy = y + Double.random(in: 0..<step, using: &generator)
                let column = Int(sx)
                let row = Int(sy)
                if column < width, row < height, pixels[row * width + column] > 127 {
                    // Bitmap rows run top-down; the scene's y runs up.
                    points.append(CGPoint(
                        x: sx - Double(width) / 2,
                        y: Double(height) / 2 - sy
                    ))
                }
                x += step
            }
            y += step
        }
        return points
    }

    // MARK: - Look

    private struct Palette {
        var faint: [NSColor]
        var bright: [NSColor]

        func pick(bright isBright: Bool, using generator: inout SystemRandomNumberGenerator) -> NSColor {
            let pool = isBright ? bright : faint
            return pool[Int.random(in: 0..<pool.count, using: &generator)]
        }

        /// Starlight on dark glass: white, ice, peach, lavender — additive.
        static let dark = Palette(
            faint: [
                NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
                NSColor(calibratedRed: 0.78, green: 0.87, blue: 1.0, alpha: 1),
                NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.7, alpha: 1),
                NSColor(calibratedRed: 0.84, green: 0.78, blue: 1.0, alpha: 1)
            ],
            bright: [
                NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
                NSColor(calibratedRed: 0.85, green: 0.92, blue: 1.0, alpha: 1),
                NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.78, alpha: 1)
            ]
        )

        /// Jewel tints on light glass: indigo, magenta, azure, violet — normal blending.
        static let light = Palette(
            faint: [
                NSColor(calibratedRed: 0.36, green: 0.33, blue: 0.95, alpha: 1),
                NSColor(calibratedRed: 0.85, green: 0.3, blue: 0.68, alpha: 1),
                NSColor(calibratedRed: 0.2, green: 0.55, blue: 0.95, alpha: 1),
                NSColor(calibratedRed: 0.58, green: 0.38, blue: 0.95, alpha: 1)
            ],
            bright: [
                NSColor(calibratedRed: 0.45, green: 0.35, blue: 1.0, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.7, alpha: 1),
                NSColor(calibratedRed: 0.2, green: 0.6, blue: 1.0, alpha: 1)
            ]
        )
    }

    /// A white radial falloff: the body of every star.
    private static let softTexture: SKTexture = texture(side: 32) { rect in
        guard let gradient = NSGradient(colorsAndLocations:
            (NSColor.white, 0),
            (NSColor.white.withAlphaComponent(0.55), 0.28),
            (NSColor.white.withAlphaComponent(0), 1)
        ) else { return }
        gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
    }

    /// The body plus four thin spikes: the bright stars.
    private static let flareTexture: SKTexture = texture(side: 64) { rect in
        guard let core = NSGradient(colorsAndLocations:
            (NSColor.white, 0),
            (NSColor.white.withAlphaComponent(0.7), 0.12),
            (NSColor.white.withAlphaComponent(0), 0.5)
        ) else { return }
        core.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        guard let spike = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0), 0),
            (NSColor.white.withAlphaComponent(0.9), 0.5),
            (NSColor.white.withAlphaComponent(0), 1)
        ) else { return }
        let mid = rect.midX
        let thickness: CGFloat = 1.6
        spike.draw(in: NSRect(x: mid - thickness / 2, y: rect.minY, width: thickness, height: rect.height), angle: 90)
        spike.draw(in: NSRect(x: rect.minX, y: mid - thickness / 2, width: rect.width, height: thickness), angle: 0)
    }

    private static func texture(side: CGFloat, draw: @escaping (NSRect) -> Void) -> SKTexture {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(rect)
            return true
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
