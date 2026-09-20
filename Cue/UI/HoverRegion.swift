import AppKit
import SwiftUI

/// Geometric hover detection for a whole SwiftUI subtree. SwiftUI's `onHover` reports "exited"
/// when the pointer moves onto a child with its own tracking (an AppKit text view, a tooltip),
/// which makes hover-revealed controls vanish as you reach for them. An `NSTrackingArea` on a
/// background view is purely geometric: the pointer is inside until it leaves the frame.
struct HoverRegion: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var area: NSTrackingArea?
        private var inside = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(next)
            area = next
            // Re-evaluate after layout so a pointer already resting here is not missed.
            if let window {
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                set(bounds.contains(point))
            }
        }

        override func mouseEntered(with event: NSEvent) { set(true) }
        override func mouseExited(with event: NSEvent) { set(false) }

        /// Never a hit target: clicks fall through to the content above.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func set(_ value: Bool) {
            guard value != inside else { return }
            inside = value
            onChange?(value)
        }
    }
}

/// `HoverRegion` with the pointer's position: the same geometric tracking area, reporting where
/// the pointer is in the subtree's own top-left coordinates and `nil` once it leaves.
struct PointerRegion: NSViewRepresentable {
    var onChange: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((CGPoint?) -> Void)?
        private var area: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(next)
            area = next
        }

        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onChange?(nil) }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func report(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onChange?(bounds.contains(point) ? point : nil)
        }
    }
}
