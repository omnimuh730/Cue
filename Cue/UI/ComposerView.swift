import AppKit
import SwiftUI

struct ComposerView: View {
    @Bindable var session: AppSession
    @State private var fieldHeight = CueTheme.composerMinHeight

    var body: some View {
        VStack(alignment: .leading, spacing: CueTheme.Spacing.xs) {
            if !session.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.attachments) { attachment in
                            if let data = Data(base64Encoded: attachment.dataURL.components(separatedBy: ",").last ?? ""),
                               let image = NSImage(data: data) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                if session.draft.isEmpty {
                    Text("Ask anything")
                        .font(.system(size: CueTheme.composerFontSize))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                GrowingComposerField(
                    text: $session.draft,
                    height: $fieldHeight,
                    onSubmit: { session.send() }
                )
                .frame(height: fieldHeight)
            }
            HStack(spacing: CueTheme.Spacing.xs) {
                listenButton
                listenPill
                Spacer()
                ModelPicker(session: session)
                Button {
                    session.send()
                } label: {
                    Image(systemName: session.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
                .help(session.isStreaming ? "Stop" : "Send")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .cueGlass(cornerRadius: CueTheme.radiusComposer, interactive: true)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .frame(maxWidth: CueTheme.readingColumnMax)
        .frame(maxWidth: .infinity)
    }

    private var listenButton: some View {
        Button {
            Task { await session.listen.toggleArmed(settings: session.settings) }
        } label: {
            Image(systemName: session.listen.status.armed ? "waveform.badge.mic" : "waveform")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Arm listen")
        .foregroundStyle(session.listen.status.armed ? Color.green : Color.secondary)
    }

    private var listenPill: some View {
        Text(session.listen.status.phase.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(phaseColor.opacity(0.18), in: Capsule())
            .foregroundStyle(phaseColor)
    }

    private var phaseColor: Color {
        switch session.listen.status.phase {
        case .armed, .listening: .green
        case .transcribing, .downloading: .orange
        case .error: .red
        case .off: .secondary
        }
    }
}
