import SwiftUI

/// Non-interactive pointer showing where remote-control input is aimed.
/// Coordinates are panel content space (origin top-left), so this must sit in an
/// overlay that ignores the title-bar safe area.
struct VirtualCursorOverlay: View {
    var state: RemoteCursorState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            PointerShape()
                .fill(Color.accentColor)
                .overlay(PointerShape().stroke(.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .frame(width: 16, height: 22)
                .offset(x: state.x, y: state.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.27, y: h * 0.6))
        path.addLine(to: CGPoint(x: w * 0.47, y: h))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.93))
        path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.56))
        path.closeSubpath()
        return path
    }
}
