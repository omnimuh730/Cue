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
                    height: $fieldHeight,
                    onSubmit: { session.send() }
                )
                .frame(height: fieldHeight)
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
