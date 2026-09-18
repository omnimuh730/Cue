import SwiftUI

/// A passage the reader selected inside a message, with where it sits on screen.
///
/// `frame` is panel content space (origin top-left), the space the SwiftUI root lays out in and
/// the one the virtual cursor already uses, so the actions can float over the selection.
struct MessageTextSelection: Equatable {
    var conversationID: UUID
    var messageID: UUID
    var text: String
    var frame: CGRect
}

/// Where a message's text view reports a finished selection; `RootView` floats the actions over
/// it. The rectangle is panel content space (origin top-left).
struct SelectMessageTextKey: EnvironmentKey {
    static let defaultValue: (String, CGRect) -> Void = { _, _ in }
}

extension EnvironmentValues {
    var selectMessageText: (String, CGRect) -> Void {
        get { self[SelectMessageTextKey.self] }
        set { self[SelectMessageTextKey.self] = newValue }
    }
}

/// The two things a selected passage can start: carry it into the composer, or branch the thread
/// from the message it sits in and carry it there.
struct SelectionActionsOverlay: View {
    var selection: MessageTextSelection
    var onAddToChat: () -> Void
    var onFork: () -> Void

    /// Gap between the selection and the actions.
    private static let gap: CGFloat = 10
    /// Kept clear of the window edges and the toolbar.
    private static let margin: CGFloat = 8

    @State private var size: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                action("Add to chat", symbol: "text.quote", help: "Quote this passage in the composer", action: onAddToChat)
                Divider().frame(height: 16)
                action("Fork", symbol: "arrow.triangle.branch", help: "Branch the chat at this message and quote the passage there", action: onFork)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .cueGlass(cornerRadius: 15, interactive: true)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // Placed from its measured size; hidden for the frame before that lands rather than
            // flashing in the wrong spot.
            .opacity(size == .zero ? 0 : 1)
            .position(position(in: geo.size))
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    /// Centered above the selection, or below it when the selection starts under the toolbar,
    /// and always inside the window.
    private func position(in canvas: CGSize) -> CGPoint {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let x = min(max(selection.frame.midX, width / 2 + Self.margin), max(width / 2 + Self.margin, canvas.width - width / 2 - Self.margin))
        let ceiling = CueTheme.headerHeight + Self.margin + height / 2
        let above = selection.frame.minY - Self.gap - height / 2
        guard above < ceiling else { return CGPoint(x: x, y: above) }
        let below = selection.frame.maxY + Self.gap + height / 2
        return CGPoint(x: x, y: min(below, max(ceiling, canvas.height - height / 2 - Self.margin)))
    }

    private func action(_ title: String, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
