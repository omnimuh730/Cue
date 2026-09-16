import AppKit
import SwiftUI

/// Modal with everything about one chat thread: cost, tokens (with prompt-cache share),
/// latency, workspace, and a per-turn breakdown. Opened from the sidebar row's info button.
struct ThreadInfoView: View {
    var conversation: Conversation
    var project: Project?
    var onClose: () -> Void
    @State private var summary: ThreadSummary?
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.12)
                ScrollView {
                    VStack(alignment: .leading, spacing: CueTheme.Spacing.sm) {
                        if let summary {
                            stats(summary)
                            turns(summary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(20)
                }
                Divider().opacity(0.12)
                footer
            }
            .frame(width: 560, height: 520)
            .cueGlass(cornerRadius: 28, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        }
        .task(id: conversation.identifier) {
            // Decoding every turn's usage JSON is not free on long threads; do it once, off-main.
            let turns = conversation.messages.sorted { $0.createdAt < $1.createdAt }.map { $0.asTurn() }
            summary = await Task.detached { ThreadSummary.build(from: turns) }.value
        }
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let project {
                        WorkspaceAvatar(letter: ProjectPaths.avatarLetter(project.name), isProject: true)
                            .scaleEffect(0.7)
                            .frame(width: 18, height: 18)
                        Text(project.name)
                        Text("·").foregroundStyle(.quaternary)
                    }
                    Text("Started \(conversation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("·").foregroundStyle(.quaternary)
                    Text("Updated \(conversation.updatedAt.formatted(.relative(presentation: .named)))")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cueGlass(cornerRadius: 14, interactive: true)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func stats(_ summary: ThreadSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            stat("Cost", Pricing.formatUsd(summary.totalCostUsd), "Estimated from list prices")
            stat("Messages", "\(summary.userMessages) · \(summary.assistantMessages)", "You · assistant")
            stat("Web searches", "\(summary.webSearchCalls)", nil)
            stat("Input tokens", ThreadSummary.formatTokens(summary.inputTokens),
                 summary.cacheHitRatio.map { "\(Int(($0 * 100).rounded()))% from prompt cache" })
            stat("Output tokens", ThreadSummary.formatTokens(summary.outputTokens),
                 summary.reasoningTokens > 0 ? "\(ThreadSummary.formatTokens(summary.reasoningTokens)) reasoning" : nil)
            stat("Latency", summary.averageFirstTokenMs.map { "\(ThreadSummary.formatMs($0)) first token" } ?? "—",
                 summary.averageTotalMs.map { "\(ThreadSummary.formatMs($0)) per reply, average" })
        }
    }

    private func stat(_ title: String, _ value: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cueGlass(cornerRadius: 14, interactive: false)
    }

    @ViewBuilder
    private func turns(_ summary: ThreadSummary) -> some View {
        if !summary.turns.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Replies")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !summary.models.isEmpty {
                        Text(summary.models.map { ModelCatalog.definition(for: $0).shortLabel }.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(summary.turns) { row in
                        turnRow(row)
                        if row.id != summary.turns.last?.id { Divider().opacity(0.12) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .cueGlass(cornerRadius: 16, interactive: false)
            }
        }
    }

    private func turnRow(_ row: ThreadSummary.TurnRow) -> some View {
        HStack(spacing: 10) {
            Text("#\(row.index)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.model.map { ModelCatalog.definition(for: $0).shortLabel } ?? "—")
                        .font(.system(size: 12, weight: .medium))
                    if let effort = row.effort {
                        Text(ModelCatalog.definition(for: effort).shortLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if row.status == .error {
                        Text("error")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
                Text(tokensLine(row))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Pricing.formatUsd(row.costUsd))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                if let first = row.timeToFirstTokenMs, let total = row.totalMs {
                    Text("\(ThreadSummary.formatMs(first)) · \(ThreadSummary.formatMs(total))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func tokensLine(_ row: ThreadSummary.TurnRow) -> String {
        var parts = ["\(ThreadSummary.formatTokens(row.inputTokens)) in"]
        if row.cachedInputTokens > 0 { parts.append("\(ThreadSummary.formatTokens(row.cachedInputTokens)) cached") }
        parts.append("\(ThreadSummary.formatTokens(row.outputTokens)) out")
        if row.reasoningTokens > 0 { parts.append("\(ThreadSummary.formatTokens(row.reasoningTokens)) reasoning") }
        if row.webSearchCalls > 0 { parts.append("\(row.webSearchCalls) search") }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let id = conversation.codexThreadID {
                Text("Codex thread \(id.prefix(8))…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help(id)
            }
            Spacer()
            Button(copied ? "Copied" : "Copy chat") {
                let text = conversation.messages
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { "\($0.role.rawValue): \($0.content)" }
                    .joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .cueGlass(cornerRadius: 16, interactive: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
