import SwiftUI

/// Centered empty-chat hero: the Cue mark wakes up, then the reading column stays quiet.
struct EmptyChatView: View {
    var project: Project?
    var onProjectSettings: () -> Void
    var onNewProject: () -> Void
    var onOpenCodeFolder: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: CueTheme.Spacing.md) {
            CueMarkSpin(pointSize: 80, spinning: appeared && !reduceMotion, style: .flick)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, CueTheme.Spacing.xs)

            OrbitingLine(
                text: "Cue",
                font: .system(size: 27, weight: .medium),
                color: .primary,
                active: appeared,
                stagger: 0.11,
                duration: 0.78
            )
            .accessibilityLabel("Cue")

            subtitle
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.22)) {
                    appeared = true
                }
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let project {
            projectCopy(project)
        } else {
            CyclingPrompt(
                lines: [
                    "Ask anything.",
                    "Attach a file, or paste a screenshot.",
                    "Type / for a skill.",
                    "Type @web_search to answer with sources.",
                    "Start a project to keep chats together."
                ],
                active: appeared
            )
        }
    }

    @ViewBuilder
    private func projectCopy(_ project: Project) -> some View {
        VStack(spacing: CueTheme.Spacing.xs) {
            if project.codeFolder != nil {
                OrbitingLine(
                    text: "Cue will read \(project.name) with Codex and answer from that codebase.",
                    font: .system(size: 14),
                    color: .secondary,
                    active: appeared,
                    stagger: 0.028,
                    duration: 0.7
                )
                OrbitingLine(
                    text: project.catalog == nil
                        ? "Not indexed — Codex explores the tree on demand."
                        : "Indexed \(project.catalogAt.map { $0.formatted(.relative(presentation: .named)) } ?? "")",
                    font: .caption,
                    color: HierarchicalShapeStyle.tertiary,
                    active: appeared,
                    stagger: 0.024,
                    duration: 0.62,
                    delay: 0.55
                )
            } else {
                OrbitingLine(
                    text: "New chat in \(project.name).",
                    font: .system(size: 14),
                    color: .secondary,
                    active: appeared,
                    stagger: 0.04,
                    duration: 0.7
                )
                OrbitingLine(
                    text: projectSummary(project),
                    font: .caption,
                    color: HierarchicalShapeStyle.tertiary,
                    active: appeared,
                    stagger: 0.024,
                    duration: 0.62,
                    delay: 0.45
                )
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Group {
            if project != nil {
                Button(action: onProjectSettings) {
                    Label("Project settings", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .cueGlass(cornerRadius: 16, interactive: true)
            } else {
                HStack(spacing: 8) {
                    Button(action: onNewProject) {
                        Label("New project", systemImage: "folder.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .cueGlass(cornerRadius: 16, interactive: true)
                    .help("Group chats with shared instructions and knowledge files")
                    Button(action: onOpenCodeFolder) {
                        Label("Open code folder", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .cueGlass(cornerRadius: 16, interactive: true)
                    .help("Chat about a local codebase through the Codex CLI")
                }
            }
        }
        .padding(.top, CueTheme.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.45), value: appeared)
    }

    private func projectSummary(_ project: Project) -> String {
        var parts: [String] = []
        if !(project.instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("custom instructions")
        }
        let files = project.knowledge.count
        if files > 0 {
            parts.append(files == 1 ? "1 knowledge file" : "\(files) knowledge files")
        }
        return parts.isEmpty
            ? "No instructions or knowledge yet — add them in project settings."
            : "Uses " + parts.joined(separator: " and ") + "."
    }
}

/// Invitation lines that remount and orbit in, one glyph at a time.
private struct CyclingPrompt: View {
    var lines: [String]
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        OrbitingLine(
            text: line,
            font: .system(size: 14),
            color: .secondary,
            active: active,
            stagger: 0.055,
            duration: 0.72
        )
        .id(index)
        .frame(minHeight: 40)
        .task(id: "\(active)-\(reduceMotion)") {
            guard active, !reduceMotion, lines.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(dwell(for: line)))
                guard !Task.isCancelled else { return }
                index = (index + 1) % lines.count
            }
        }
    }

    private var line: String {
        guard lines.indices.contains(index) else { return lines.first ?? "" }
        return lines[index]
    }

    /// Letter cascade + landing, then a pause long enough to read.
    private func dwell(for text: String) -> TimeInterval {
        0.12 + Double(text.count) * 0.055 + 0.72 + 2.15
    }
}

/// A line whose glyphs spiral onto the stage in order.
private struct OrbitingLine<Foreground: ShapeStyle>: View {
    var text: String
    var font: Font
    var color: Foreground
    var active: Bool
    var stagger: TimeInterval
    var duration: TimeInterval
    var delay: TimeInterval = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                OrbitingGlyph(
                    character: String(character),
                    font: font,
                    color: color,
                    delay: delay + Double(index) * stagger,
                    duration: duration,
                    parity: index,
                    active: active && !reduceMotion
                )
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct OrbitingGlyph<Foreground: ShapeStyle>: View {
    var character: String
    var font: Font
    var color: Foreground
    var delay: TimeInterval
    var duration: TimeInterval
    var parity: Int
    var active: Bool

    @State private var progress: CGFloat = 0

    var body: some View {
        let pose = LetterOrbit.pose(isSpace ? 1 : progress, parity: parity)
        Text(character)
            .font(font)
            .foregroundStyle(color)
            .opacity(pose.opacity)
            .blur(radius: pose.blur)
            .scaleEffect(pose.scale)
            .rotationEffect(.degrees(pose.rotation))
            .offset(pose.offset)
            .task(id: active) {
                if !active || isSpace {
                    progress = 1
                    return
                }
                progress = 0
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.16, 0.92, 0.22, 1, duration: duration)) {
                    progress = 1
                }
            }
    }

    private var isSpace: Bool { character == " " }
}
