import SwiftUI

/// Offered right after a project folder is opened: build a local map catalog so Codex can
/// find context faster. Skipping keeps the project; Codex will explore the tree on its own.
struct IndexProjectDialog: View {
    var project: Project
    var indexing: Bool
    var error: String?
    var onIndex: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { if !indexing { onSkip() } }

            VStack(alignment: .leading, spacing: CueTheme.Spacing.sm) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                    Text("Index this project?")
                        .font(.system(size: 17, weight: .semibold))
                }
                Text("Cue can build a map catalog of **\(project.name)** — folders and key files — so Codex can find context faster. This stays on your Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(project.folderPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(project.folderPath)

                if indexing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Building map catalog…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("Skip", action: onSkip)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .cueGlass(cornerRadius: 16, interactive: true)
                        .disabled(indexing)
                    Button(indexing ? "Indexing…" : "Index", action: onIndex)
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                        .foregroundStyle(.white)
                        .background(Color.accentColor.opacity(indexing ? 0.6 : 1), in: Capsule())
                        .disabled(indexing)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 440)
            .cueGlass(cornerRadius: 24, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        }
        .accessibilityAddTraits(.isModal)
    }
}
