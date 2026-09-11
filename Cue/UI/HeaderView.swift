import SwiftUI

struct HeaderView: View {
    @Bindable var session: AppSession

    var body: some View {
        HStack(spacing: CueTheme.Spacing.sm) {
            if !session.sidebarOpen {
                Button {
                    session.sidebarOpen = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show sidebar")
            }

            Text(session.activeConversation?.title ?? "Cue")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .allowsHitTesting(false)

            Spacer(minLength: 8)

            if let summary = session.activeConversation, summary.totalCostUsd > 0 {
                Text(Pricing.formatUsd(summary.totalCostUsd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, session.sidebarOpen ? CueTheme.Spacing.md : CueTheme.trafficClearance)
        .padding(.trailing, CueTheme.Spacing.md)
        .frame(height: CueTheme.headerHeight)
        .frame(maxWidth: .infinity)
        .cueGlass(cornerRadius: 0)
        .cueWindowDrag()
    }
}
