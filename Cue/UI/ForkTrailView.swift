import SwiftUI

/// Where a thread diverged: the branches cut at one turn, drawn under it.
///
/// The tab bar says which branches a chat has; this says where each one left. Opening a branch
/// here shows the turns it added after the fork as a thread under the message they follow, and any
/// row of that thread opens the branch on that turn.
struct ForkTrailView: View {
    @Bindable var session: AppSession
    var forks: [Conversation]

    /// Branch whose follow-up thread is open; nil keeps the trail to one quiet line.
    @State private var expandedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chips
            if let expanded = forks.first(where: { $0.identifier == expandedID }) {
                thread(expanded)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: expandedID)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(forks.count == 1 ? "Forked here" : "Forked here \(forks.count) times")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            ForEach(forks, id: \.identifier) { branch in
                chip(branch)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ branch: Conversation) -> some View {
        let isOpen = expandedID == branch.identifier
        let turns = session.branchContinuation(of: branch).count
        return Button {
            expandedID = isOpen ? nil : branch.identifier
        } label: {
            HStack(spacing: 4) {
                Text(session.branchName(branch))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if turns > 0 {
                    Text("\(turns)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
                Capsule().fill(isOpen ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(session.branchOrigin(of: branch) ?? "Open this branch's thread")
        .accessibilityLabel("Branch \(session.branchName(branch)), \(turns) \(turns == 1 ? "turn" : "turns")")
    }

    /// The branch's own turns, under a rail so they read as a thread off the message above rather
    /// than as more of the chat being read.
    private func thread(_ branch: Conversation) -> some View {
        let turns = session.branchContinuation(of: branch)
        return HStack(alignment: .top, spacing: 8) {
            Capsule()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if turns.isEmpty {
                    Text("Nothing asked in this branch yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 3)
                } else {
                    ForEach(turns, id: \.identifier) { turn in
                        turnRow(turn, in: branch)
                    }
                }
                Button {
                    session.openBranch(branch)
                } label: {
                    Label("Open \(session.branchName(branch))", systemImage: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func turnRow(_ message: Message, in branch: Conversation) -> some View {
        Button {
            session.openBranch(branch, at: message.identifier)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message.role == .user ? "You" : "Cue")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .leading)
                Text(ChatBranching.preview(message.content))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(session.branchName(branch)) at this turn")
    }
}
