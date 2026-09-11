import SwiftUI

struct HeaderView: View {
    @Bindable var session: AppSession

    var body: some View {
        HStack(spacing: CueTheme.Spacing.sm) {
            Button {
                session.sidebarOpen.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .help("Toggle sidebar")

            Text(session.activeConversation?.title ?? "Cue")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer()
            if let summary = session.activeConversation, summary.totalCostUsd > 0 {
                Text(Pricing.formatUsd(summary.totalCostUsd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, CueTheme.Spacing.md)
        .frame(height: CueTheme.headerHeight)
        .cueGlass(cornerRadius: 0)
    }
}
