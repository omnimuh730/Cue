#!/usr/bin/env swift
import AppKit

/// Renders `circle.dashed.inset.filled` into the macOS app icon set.
/// The glyph matches the menu-bar mark; the square fill is for Finder / About.

let symbolName = "circle.dashed.inset.filled"
let outputDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "Cue/Assets.xcassets/AppIcon.appiconset")

struct Spec {
    var filename: String
    var pixels: Int
}

let specs: [Spec] = [
    .init(filename: "icon_16x16.png", pixels: 16),
    .init(filename: "icon_16x16@2x.png", pixels: 32),
    .init(filename: "icon_32x32.png", pixels: 32),
    .init(filename: "icon_32x32@2x.png", pixels: 64),
    .init(filename: "icon_128x128.png", pixels: 128),
    .init(filename: "icon_128x128@2x.png", pixels: 256),
    .init(filename: "icon_256x256.png", pixels: 256),
    .init(filename: "icon_256x256@2x.png", pixels: 512),
    .init(filename: "icon_512x512.png", pixels: 512),
    .init(filename: "icon_512x512@2x.png", pixels: 1024),
]

_ = NSApplication.shared

guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    FileHandle.standardError.write(Data("Missing SF Symbol \(symbolName)\n".utf8))
    exit(1)
}

func render(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not allocate bitmap")
    }
    rep.size = NSSize(width: size, height: size)

    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            fatalError("Could not create graphics context")
        }
        context.imageInterpolation = .high
        NSGraphicsContext.current = context

        let top = NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1)
        let bottom = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
        let gradient = NSGradient(starting: top, ending: bottom)!
        gradient.draw(in: NSRect(origin: .zero, size: NSSize(width: size, height: size)), angle: 90)

        let glow = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.10),
            NSColor.white.withAlphaComponent(0)
        ])!
        let glowRect = NSRect(x: size * 0.08, y: size * 0.22, width: size * 0.84, height: size * 0.84)
        glow.draw(in: glowRect, relativeCenterPosition: .zero)

        let weight: NSFont.Weight = pixels <= 32 ? .semibold : .medium
        let pointSize = size * (pixels <= 32 ? 0.62 : 0.54)
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: .large)
            .applying(.preferringMonochrome())
        guard let symbol = base.withSymbolConfiguration(config) else {
            fatalError("Could not configure symbol")
        }

        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let symbolSize = tinted.size
        let rect = NSRect(
            x: (size - symbolSize.width) / 2,
            y: (size - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    return rep
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
for spec in specs {
    let rep = render(pixels: spec.pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(spec.filename)")
    }
    try png.write(to: outputDir.appendingPathComponent(spec.filename))
    print("Wrote \(spec.filename) (\(spec.pixels)px)")
}
