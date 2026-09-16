import AppKit
import SwiftUI

/// One fenced code block, framed as its own panel.
///
/// Code used to render as an `NSTextBlock` inside the prose run, whose 6% fill disappeared against
/// the window's glass. A block the reader is meant to lift out of the answer needs to read as a
/// separate object: a solid ground for contrast (the one place the visual contract allows a flat
/// fill), the language it is in, and a copy button of its own.
struct CodeBlockView: View {
    var language: String
    var source: String

    @State private var hovering = false

    private var title: String {
        let trimmed = language.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Code" : CodeLanguage.label(for: trimmed)
    }

    var body: some View {
        CodeBlockFrame(title: title, source: source, hovering: $hovering) {
            NumberedCodeView(text: MarkdownTextBuilder.code(source))
                .padding(.trailing, CueTheme.Spacing.sm)
                .padding(.vertical, 10)
        }
    }
}

/// The shared chrome around a code or diagram block: label, copy button, and a ground solid
/// enough to read against the window's glass.
struct CodeBlockFrame<Content: View, Accessory: View>: View {
    var title: String
    /// What the copy button puts on the pasteboard.
    var source: String
    @Binding var hovering: Bool
    @ViewBuilder var content: Content
    /// Extra header control, drawn beside the copy button.
    @ViewBuilder var accessory: Accessory

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var copied = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.14)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Flat fill for text contrast — the one exception to materials-over-fills.
            shape.fill(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : 0.7))
        }
        .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
        .clipShape(shape)
        .onHover { hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            accessory
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(hovering ? 0.08 : 0), in: Capsule())
            // Always legible on hover; faint otherwise so a long answer stays quiet.
            .opacity(hovering || copied ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.15), value: hovering || copied)
            .help("Copy this block")
            .accessibilityLabel("Copy code")
        }
        .padding(.horizontal, CueTheme.Spacing.sm)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
    }
}

extension CodeBlockFrame where Accessory == EmptyView {
    init(title: String, source: String, hovering: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(title: title, source: source, hovering: hovering, content: content, accessory: { EmptyView() })
    }
}

/// Display names for the fence languages that have one; anything else shows as written.
nonisolated enum CodeLanguage {
    private static let names: [String: String] = [
        "bash": "Bash", "c": "C", "cpp": "C++", "c++": "C++", "cs": "C#", "csharp": "C#",
        "css": "CSS", "diff": "Diff", "go": "Go", "html": "HTML", "java": "Java",
        "javascript": "JavaScript", "js": "JavaScript", "json": "JSON", "kotlin": "Kotlin",
        "md": "Markdown", "markdown": "Markdown", "mermaid": "Mermaid", "objc": "Objective-C",
        "php": "PHP", "py": "Python", "python": "Python", "rb": "Ruby", "ruby": "Ruby",
        "rust": "Rust", "rs": "Rust", "sh": "Shell", "shell": "Shell", "sql": "SQL",
        "swift": "Swift", "toml": "TOML", "ts": "TypeScript", "tsx": "TSX",
        "typescript": "TypeScript", "xml": "XML", "yaml": "YAML", "yml": "YAML", "zsh": "Zsh"
    ]

    static func label(for language: String) -> String {
        names[language.lowercased()] ?? language
    }
}
