import AppKit
import SwiftUI

enum CueTheme {
    static let symbolName = "circle.dashed.inset.filled"
    static let sidebarWidth: CGFloat = 282
    /// Height of the unified-compact title band; the traffic lights are centered in it.
    static let headerHeight: CGFloat = 40
    static let trafficClearance: CGFloat = 84
    static let sidebarInset: CGFloat = 8
    /// Narrower than this and the sidebar would squeeze the transcript into a column too thin to
    /// read, so it floats over the chat instead of sitting beside it.
    static let sidebarSplitMinWidth: CGFloat = 700
    /// Kept clear to the right of a floating sidebar so the chat behind it stays visible.
    static let sidebarOverlayGutter: CGFloat = 52
    static let readingColumnMax: CGFloat = 800
    static let radiusRow: CGFloat = 8
    static let radiusPanel: CGFloat = 16
    static let radiusComposer: CGFloat = 28
    static let composerInset: CGFloat = 18
    static let composerFontSize: CGFloat = 15.5
    static let composerLineHeight: CGFloat = 20
    static let composerMinLines = 1
    static let composerMaxLines = 10

    static var composerMinHeight: CGFloat { composerLineHeight * CGFloat(composerMinLines) }
    static var composerMaxHeight: CGFloat { composerLineHeight * CGFloat(composerMaxLines) }

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
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.92), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
        } else {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .clear.interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
    }
}

extension View {
    func cueGlass(cornerRadius: CGFloat = CueTheme.radiusPanel, interactive: Bool = false) -> some View {
        modifier(CueGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

struct CueMark: View {
    var pointSize: CGFloat = 18

    var body: some View {
        Image(systemName: CueTheme.symbolName)
            .font(.system(size: pointSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .accessibilityHidden(true)
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
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 0))
            }
        }
        .ignoresSafeArea()
    }
}

struct CueGlassField<Content: View>: View {
    var title: String
    var help: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
            if let help {
                Text(help)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cueGlass(cornerRadius: 18, interactive: true)
    }
}

struct CueGlassToggle: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .cueGlass(cornerRadius: 16, interactive: true)
    }
}

struct CueLiveSecureField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = .labelColor
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text, field.currentEditor() == nil {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
