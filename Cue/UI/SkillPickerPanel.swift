import AppKit
import SwiftUI

/// Skill list shown above the composer while the draft starts with `/`. Keyboard navigation is
/// driven by the composer field (arrows, Return, Tab, Escape) so the caret never leaves the text.
struct SkillPickerPanel: View {
    var skills: [SkillDefinition]
    var query: String
    var selectedIndex: Int
    var globalRoot: URL
    var onPick: (SkillDefinition) -> Void
    var onHover: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Skills")
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

            if skills.isEmpty {
                emptyRow
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(skills.enumerated()), id: \.element.id) { item in
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
                        guard skills.indices.contains(index) else { return }
                        proxy.scrollTo(skills[index].id)
                    }
                }
            }
        }
        .frame(width: 380)
        .cueGlass(cornerRadius: 14, interactive: true)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .accessibilityLabel("Skill picker")
    }

    private func row(_ skill: SkillDefinition, selected: Bool) -> some View {
        Button {
            onPick(skill)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.purple)
                    .frame(width: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("/\(skill.name)")
                            .font(.system(size: 13, weight: .medium))
                        if skill.scope == .project {
                            Text("project")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if !skill.description.isEmpty {
                        Text(skill.description)
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

    private var emptyRow: some View {
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
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
