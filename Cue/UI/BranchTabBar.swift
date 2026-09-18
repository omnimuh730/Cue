import SwiftUI

/// Tabs for a forked thread. A chat that was never forked has one branch and no bar; forking
/// makes the bar appear with `main` and the new branch side by side, so both versions of the
/// conversation stay one click apart.
struct BranchTabBar: View {
    @Bindable var session: AppSession
    @State private var hoveredID: UUID?
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        let tabs = session.branchTabs
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .help("Branches of this chat")
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs, id: \.identifier) { branch in
                        tab(branch)
                    }
                }
                .padding(.vertical, 4)
            }
            Button {
                session.forkActiveConversation()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fork this branch at its newest turn")
            .accessibilityLabel("New branch")
        }
        .padding(.horizontal, CueTheme.Spacing.sm)
        .frame(height: CueTheme.branchTabBarHeight)
        .frame(maxWidth: .infinity)
        .cueGlass(cornerRadius: 0, interactive: true)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func tab(_ branch: Conversation) -> some View {
        let isActive = session.activeID == branch.identifier
        let isHovered = hoveredID == branch.identifier
        let streaming = session.isStreaming(branch)
        let unread = session.isUnread(branch)
        let isMain = branch.forkedFromID == nil

        return HStack(spacing: 5) {
            if renamingID == branch.identifier {
                TextField("Branch name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 96)
                    .focused($renameFocused)
                    .onSubmit { commitRename(branch) }
                    .onExitCommand { renamingID = nil }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused, renamingID == branch.identifier { commitRename(branch) }
                    }
            } else {
                Text(session.branchName(branch))
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            if streaming {
                CueMarkSpin(pointSize: 11, spinning: true, style: .busy)
            } else if unread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("New reply")
            }
            if !isMain, isHovered || isActive {
                Button {
                    session.deleteBranch(branch)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete this branch")
                .accessibilityLabel("Delete branch")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.22) : (isHovered ? Color.primary.opacity(0.06) : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: CueTheme.radiusRow, style: .continuous))
        .onTapGesture { session.select(branch.identifier) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(branch) })
        .contextMenu { menu(branch) }
        .onHover { hovering in
            hoveredID = hovering ? branch.identifier : (hoveredID == branch.identifier ? nil : hoveredID)
        }
        .help(session.branchOrigin(of: branch) ?? "The chat every branch here was forked from")
        .accessibilityLabel("Branch \(session.branchName(branch))")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private func menu(_ branch: Conversation) -> some View {
        Button("Rename branch…") { beginRename(branch) }
        Button("Fork from here") {
            session.select(branch.identifier)
            session.forkActiveConversation()
        }
        if branch.forkedFromID != nil {
            Divider()
            Button("Delete branch", role: .destructive) { session.deleteBranch(branch) }
        }
    }

    private func beginRename(_ branch: Conversation) {
        renameText = session.branchName(branch)
        renamingID = branch.identifier
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(_ branch: Conversation) {
        guard renamingID == branch.identifier else { return }
        renamingID = nil
        session.renameBranch(branch, to: renameText)
    }
}
