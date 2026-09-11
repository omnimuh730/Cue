import SwiftUI

enum CueTheme {
    static let sidebarWidth: CGFloat = 282
    static let headerHeight: CGFloat = 44
    static let readingColumnMax: CGFloat = 800
    static let radiusRow: CGFloat = 8
    static let radiusPanel: CGFloat = 16
    static let radiusComposer: CGFloat = 28
    static let composerInset: CGFloat = 18

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

struct CueGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        } else {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
        }
    }
}

extension View {
    func cueGlass(cornerRadius: CGFloat = CueTheme.radiusPanel, interactive: Bool = false) -> some View {
        modifier(CueGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

struct CueWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea()
    }
}
