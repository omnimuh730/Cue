import AppKit
import SwiftUI

struct ComposerView: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: CueTheme.Spacing.xs) {
            if !session.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.attachments) { attachment in
                            ComposerAttachmentChip(
                                attachment: attachment,
                                onPreview: { session.previewAttachment = attachment },
                                onRemove: {
                                    session.attachments.removeAll { $0.id == attachment.id }
                                    if session.previewAttachment?.id == attachment.id {
                                        session.previewAttachment = nil
                                    }
                                }
                            )
                        }
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                if session.draft.isEmpty {
                    Text(placeholder)
                        .font(.system(size: CueTheme.composerFontSize))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                GrowingComposerField(
                    text: $session.draft,
                    onSubmit: { session.send() }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack(spacing: CueTheme.Spacing.xs) {
                listenButton
                listenPill
                if backgroundStreams > 0 {
                    backgroundPill
                }
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
                .background(session.isStreaming ? Color.red.opacity(0.85) : Color.accentColor, in: Circle())
                .foregroundStyle(.white)
                .help(session.isStreaming ? "Stop this response" : "Send")
                .animation(.easeInOut(duration: 0.15), value: session.isStreaming)
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

    private var placeholder: String {
        if let project = session.activeProject { return "Ask about \(project.name)" }
        return "Ask anything"
    }

    /// Chats other than the one on screen that are still receiving a reply.
    private var backgroundStreams: Int {
        session.streamingIDs.subtracting([session.activeID].compactMap { $0 }).count
    }

    private var backgroundPill: some View {
        HStack(spacing: 5) {
            StreamingIndicator()
                .frame(width: 18)
            Text(backgroundStreams == 1 ? "1 chat responding" : "\(backgroundStreams) chats responding")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
        .foregroundStyle(Color.accentColor)
        .transition(.opacity)
        .help("Replies keep streaming in the background; pick the chat in the sidebar to read it")
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
        let status = session.listen.status
        return HStack(spacing: 5) {
            Text(pillLabel(status))
                .font(.caption)
                .lineLimit(1)
            if status.phase == .listening || status.phase == .armed {
                Capsule()
                    .fill(phaseColor)
                    .frame(width: max(2, 22 * CGFloat(min(1, status.inputLevel * 4))), height: 4)
                    .frame(width: 22, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(phaseColor.opacity(0.18), in: Capsule())
        .foregroundStyle(phaseColor)
        .help(status.error ?? pillHelp(status))
    }

    private func pillLabel(_ status: ListenStatus) -> String {
        switch status.phase {
        case .error: status.error.map { "error · \($0)" }?.prefix(72).description ?? "error"
        case .downloading:
            status.downloadProgress.map { "loading \(Int($0 * 100))%" } ?? "loading model"
        default: status.phase.rawValue
        }
    }

    private func pillHelp(_ status: ListenStatus) -> String {
        switch status.phase {
        case .off: "Listen is off. Click the waveform to arm speaker listen."
        case .armed: "Armed. Speech from the speakers is detected automatically. The bar shows input level."
        case .listening: "Hearing speech…"
        case .transcribing: "Transcribing the last phrase."
        case .downloading: "Loading the Whisper model. First use downloads and compiles it; this can take a minute."
        case .error: "Listen error."
        }
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
