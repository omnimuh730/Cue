import AppKit
import SwiftUI

struct ComposerView: View {
    @Bindable var session: AppSession
    @State private var pickerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: CueTheme.Spacing.xs) {
            if !session.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
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
            TextEditor(text: $session.draft)
                .font(.system(size: 15))
                .frame(minHeight: 44, maxHeight: 140)
                .scrollContentBackground(.hidden)
            HStack(spacing: CueTheme.Spacing.xs) {
                listenButton
                listenPill
                Spacer()
                ModelPicker(settings: session.settings) { model, effort in
                    session.settingsStore.patch { settings in
                        settings.model = model
                        settings.reasoningEffort = effort
                    }
                }
                Button {
                    session.send()
                } label: {
                    Image(systemName: session.isStreaming ? "stop.fill" : "arrow.up")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
                .help(session.isStreaming ? "Stop" : "Send")
            }
        }
        .padding(CueTheme.Spacing.md)
        .cueGlass(cornerRadius: CueTheme.radiusComposer, interactive: true)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .frame(maxWidth: CueTheme.readingColumnMax)
        .frame(maxWidth: .infinity)
        .onSubmit(of: .text) {
            session.send()
        }
    }

    private var listenButton: some View {
        Button {
            Task { await session.listen.toggleArmed(settings: session.settings) }
        } label: {
            Image(systemName: session.listen.status.armed ? "waveform.badge.mic" : "waveform")
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
