import AppKit
import SwiftUI

struct ComposerView: View {
    @Bindable var session: AppSession
    @State private var skillIndex = 0
    @State private var skillPickerDismissed = false

    /// Text after a leading `/`, while the user is still typing a skill name.
    private var skillQuery: String? {
        skillPickerDismissed ? nil : SkillInvocation.query(in: session.draft)
    }

    private var skillMatches: [SkillDefinition] {
        SkillInvocation.filter(session.skills.skills, query: skillQuery ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let query = skillQuery {
                SkillPickerPanel(
                    skills: skillMatches,
                    query: query,
                    selectedIndex: skillIndex,
                    globalRoot: session.skills.globalRoot,
                    onPick: { pickSkill($0) },
                    onHover: { skillIndex = $0 }
                )
                .transition(.opacity)
            }
            if showsTranscript {
                TranscriptStrip(
                    log: session.listen.transcript,
                    listening: session.listen.status.armed,
                    answerShortcut: HotkeyCatalog.displayLabel(for: session.settings.hotkeyMap[.answerLastSentence] ?? ""),
                    onAnswer: { session.answerFromTranscript(sentences: 1) },
                    onQuote: { session.quoteTranscript($0) },
                    onClear: { session.listen.clearTranscript() }
                )
                .transition(.opacity)
            }
            composer
        }
        .animation(.easeInOut(duration: 0.15), value: showsTranscript)
        .frame(maxWidth: CueTheme.readingColumnMax)
        .frame(maxWidth: .infinity)
            .onChange(of: session.draft) { previous, next in
                let wasOpen = SkillInvocation.query(in: previous) != nil
                let isOpen = SkillInvocation.query(in: next) != nil
                if isOpen, !wasOpen {
                    // Fresh `/`: rescan so a file saved a moment ago shows up.
                    skillPickerDismissed = false
                    skillIndex = 0
                    session.refreshSkills()
                } else if !isOpen {
                    skillPickerDismissed = false
                } else if wasOpen {
                    skillIndex = 0
                }
            }
            .animation(.easeInOut(duration: 0.12), value: skillQuery == nil)
    }

    /// The strip appears once listen is armed and stays while there is something heard to act on.
    private var showsTranscript: Bool {
        session.listen.status.armed || !session.listen.transcript.isEmpty
    }

    private func pickSkill(_ skill: SkillDefinition) {
        session.attachSkill(skill)
        skillIndex = 0
    }

    /// Arrow keys, Return, Tab, and Escape drive the picker while it is open.
    private func handleCommand(_ selector: Selector) -> Bool {
        guard skillQuery != nil else { return false }
        let matches = skillMatches
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            guard !matches.isEmpty else { return true }
            skillIndex = (skillIndex - 1 + matches.count) % matches.count
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !matches.isEmpty else { return true }
            skillIndex = (skillIndex + 1) % matches.count
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            guard matches.indices.contains(skillIndex) else { return selector == #selector(NSResponder.insertTab(_:)) }
            pickSkill(matches[skillIndex])
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            skillPickerDismissed = true
            return true
        default:
            return false
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: CueTheme.Spacing.xs) {
            if !session.attachments.isEmpty || !session.importingNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(session.importingNames.enumerated()), id: \.offset) { item in
                            ImportingChip(name: item.element)
                        }
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
                    onSubmit: { session.send() },
                    onFiles: { session.importFiles($0) },
                    onImage: { session.addPastedImage($0) },
                    onCommand: { handleCommand($0) }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack(spacing: CueTheme.Spacing.xs) {
                attachButton
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
                    Image(systemName: session.composerPrimaryAction == .stop ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(session.composerPrimaryAction == .stop ? Color.red.opacity(0.85) : Color.accentColor, in: Circle())
                .foregroundStyle(.white)
                .help(session.composerPrimaryAction == .stop ? "Stop this response" : "Send")
                .animation(.easeInOut(duration: 0.15), value: session.composerPrimaryAction)
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
        if let project = session.activeProject {
            return project.codeFolder != nil ? "Ask about \(project.name)" : "Message \(project.name)"
        }
        return "Ask anything · type / for skills"
    }

    /// Chats other than the one on screen that are still receiving a reply.
    private var backgroundStreams: Int {
        session.streamingIDs.subtracting([session.activeID].compactMap { $0 }).count
    }

    private var backgroundPill: some View {
        HStack(spacing: 5) {
            CueMarkSpin(pointSize: 14, spinning: true, style: .busy)
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

    private var attachButton: some View {
        Button {
            session.pickFiles()
        } label: {
            Image(systemName: "paperclip")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Attach files: PDF, Word, Excel, PowerPoint, images, or text. You can also drop or paste files here.")
        .foregroundStyle(Color.secondary)
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
