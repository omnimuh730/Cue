import AppKit
import SwiftUI

/// Something the composer can attach from a typed trigger: a `/skill` or an `@tool`.
protocol ComposerPickable: Identifiable, Equatable {
    /// What the row shows, trigger included ("/coding", "@web_search").
    var pickerTitle: String { get }
    var pickerDescription: String { get }
    var pickerSymbol: String { get }
    var pickerTint: Color { get }
    /// A small label after the title ("project" for repo skills); nil for none.
    var pickerBadge: String? { get }
}

extension SkillDefinition: ComposerPickable {
    var pickerTitle: String { "/\(name)" }
    var pickerDescription: String { description }
    var pickerSymbol: String { "sparkles" }
    var pickerTint: Color { .purple }
    var pickerBadge: String? { scope == .project ? "project" : nil }
}

extension ComposerTool: ComposerPickable {
    var pickerTitle: String { "@\(rawValue)" }
    var pickerDescription: String { description }
    var pickerSymbol: String { symbol }
    var pickerTint: Color { .accentColor }
    var pickerBadge: String? { nil }
}

/// The list shown above the composer while a `/` or `@` token is being typed. Keyboard
/// navigation is driven by the composer field (arrows, Return, Tab, Escape) so the caret never
/// leaves the text.
struct ComposerPickerPanel<Item: ComposerPickable, Empty: View>: View {
    var title: String
    var items: [Item]
    var selectedIndex: Int
    var onPick: (Item) -> Void
    var onHover: (Int) -> Void
    @ViewBuilder var empty: Empty

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("↑↓ to choose · ⏎ to attach · esc to dismiss")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if items.isEmpty {
                empty
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { item in
                                row(item.element, selected: item.offset == selectedIndex)
                                    .id(item.element.id)
                                    .onHover { if $0 { onHover(item.offset) } }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: selectedIndex) { _, index in
                        guard items.indices.contains(index) else { return }
                        proxy.scrollTo(items[index].id)
                    }
                }
            }
        }
        .frame(width: 380)
        .cueGlass(cornerRadius: 14, interactive: true)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .accessibilityLabel("\(title) picker")
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.pickerSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.pickerTint)
                    .frame(width: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.pickerTitle)
                            .font(.system(size: 13, weight: .medium))
                        if let badge = item.pickerBadge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if !item.pickerDescription.isEmpty {
                        Text(item.pickerDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Skill list for the `/` trigger, with the "add a file" hint when nothing matches.
struct SkillPickerPanel: View {
    var skills: [SkillDefinition]
    var query: String
    var selectedIndex: Int
    var globalRoot: URL
    var onPick: (SkillDefinition) -> Void
    var onHover: (Int) -> Void

    var body: some View {
        ComposerPickerPanel(title: "Skills", items: skills, selectedIndex: selectedIndex, onPick: onPick, onHover: onHover) {
            VStack(alignment: .leading, spacing: 6) {
                Text(query.isEmpty ? "No skills yet." : "No skill matches “\(query)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Add `name.md` or `name/SKILL.md` files to \(globalRoot.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Button("Open skills folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([globalRoot])
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}

/// Tool list for the `@` trigger.
struct ToolPickerPanel: View {
    var tools: [ComposerTool]
    var query: String
    var selectedIndex: Int
    var onPick: (ComposerTool) -> Void
    var onHover: (Int) -> Void

    var body: some View {
        ComposerPickerPanel(title: "Tools", items: tools, selectedIndex: selectedIndex, onPick: onPick, onHover: onHover) {
            Text("No tool matches “\(query)”.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
