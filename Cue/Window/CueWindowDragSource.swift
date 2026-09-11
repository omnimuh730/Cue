import AppKit
import SwiftUI

/// Transparent AppKit region that moves the Cue panel. Clicks on SwiftUI
/// controls in front of it still go to those controls.
final class CueWindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct CueWindowDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> CueWindowDragNSView {
        CueWindowDragNSView()
    }

    func updateNSView(_ nsView: CueWindowDragNSView, context: Context) {}
}

extension View {
    func cueWindowDrag() -> some View {
        background {
            CueWindowDragSource()
        }
    }
}
