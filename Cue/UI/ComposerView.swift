import AppKit
import SwiftUI

struct ComposerView: View {
    @Bindable var session: AppSession
    @State private var skillIndex = 0
    @State private var skillPickerDismissed = false
    @State private var toolIndex = 0
    @State private var toolPickerDismissed = false
    @State private var sendHovering = false

    /// Text after a `/` the user is typing, anywhere in the draft, while the skill name is still open.
    private var skillQuery: String? {
        skillPickerDismissed ? nil : SkillInvocation.query(in: session.draft)
    }

    private var skillMatches: [SkillDefinition] {
        SkillInvocation.filter(session.skills.skills, query: skillQuery ?? "")
    }

    /// Text after an `@` the user is typing, anywhere in the draft. `/` wins when both are open.
    private var toolQuery: String? {
        guard skillQuery == nil, !toolPickerDismissed else { return nil }
        return MentionInvocation.query(in: session.draft)
    }

    private var toolMatches: [ComposerTool] {
        MentionInvocation.filter(ComposerTool.allCases, query: toolQuery ?? "")
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let query = toolQuery {
                ToolPickerPanel(
                    tools: toolMatches,
                    query: query,
                    selectedIndex: toolIndex,
                    onPick: { pickTool($0) },
                    onHover: { toolIndex = $0 }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .animation(CueMotion.panel, value: showsTranscript)
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
                let mentionWasOpen = MentionInvocation.query(in: previous) != nil
                let mentionIsOpen = MentionInvocation.query(in: next) != nil
                if mentionIsOpen, !mentionWasOpen {
                    toolPickerDismissed = false
                    toolIndex = 0
                } else if !mentionIsOpen {
                    toolPickerDismissed = false
                } else if mentionWasOpen {
                    toolIndex = 0
                }
            }
            .animation(CueMotion.panel, value: skillQuery == nil && toolQuery == nil)
    }

    private func pickTool(_ tool: ComposerTool) {
        session.attachTool(tool)
        toolIndex = 0
    }

    /// The strip appears once listen is armed and stays while there is something heard to act on.
    private var showsTranscript: Bool {
        session.listen.status.armed || !session.listen.transcript.isEmpty
    }

    private func pickSkill(_ skill: SkillDefinition) {
        session.attachSkill(skill)
        skillIndex = 0
    }

    /// Arrow keys, Return, Tab, and Escape drive whichever picker is open.
    private func handleCommand(_ selector: Selector) -> Bool {
        if skillQuery != nil {
            return handlePickerCommand(selector, count: skillMatches.count, index: &skillIndex) { index in
                pickSkill(skillMatches[index])
            } dismiss: {
                skillPickerDismissed = true
            }
        }
        if toolQuery != nil {
            return handlePickerCommand(selector, count: toolMatches.count, index: &toolIndex) { index in
                pickTool(toolMatches[index])
            } dismiss: {
                toolPickerDismissed = true
            }
        }
        return false
    }

    private func handlePickerCommand(
        _ selector: Selector,
        count: Int,
        index: inout Int,
        pick: (Int) -> Void,
        dismiss: () -> Void
    ) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            guard count > 0 else { return true }
            index = (index - 1 + count) % count
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard count > 0 else { return true }
            index = (index + 1) % count
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            guard index < count else { return selector == #selector(NSResponder.insertTab(_:)) }
            pick(index)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
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
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .cueGlass(cornerRadius: CueTheme.radiusComposer, interactive: true, sheen: true)
        // While the reply streams, the composer's edge carries the same light as the orb.
        .cueAuroraGlow(active: session.isStreaming, cornerRadius: CueTheme.radiusComposer)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .frame(maxWidth: CueTheme.readingColumnMax)
        .frame(maxWidth: .infinity)
    }

    /// The one primary action. A flat disc — accent to send, red to stop — that dips on press,
    /// lifts and glows under the pointer, and throws a short sparkle when a draft becomes
    /// sendable and again as it goes.
    private var sendButton: some View {
        let stop = session.composerPrimaryAction == .stop
        let tint = stop ? Color.red : Color.accentColor
        return Button {
            session.send()
        } label: {
            Image(systemName: stop ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background {
                    // A flat disc; the pointer is answered with a tinted glow, not a gradient.
                    Circle()
                        .fill(tint.opacity(stop ? 0.85 : 1))
                        .shadow(color: tint.opacity(sendHovering ? 0.5 : 0.18), radius: sendHovering ? 12 : 4, y: 2)
                }
                .cueSparkleBurst(on: session.hasComposerPayload, strength: 1.1)
                // Plain buttons hit-test only the glyph; make the whole disc clickable.
                .contentShape(Circle())
        }
        .buttonStyle(CuePressButtonStyle())
        .foregroundStyle(.white)
        .cueHoverLift(1.08)
        .onHover { sendHovering = $0 }
        .help(stop ? "Stop this response" : "Send")
        .animation(CueMotion.control, value: session.composerPrimaryAction)
        .animation(CueMotion.control, value: sendHovering)
    }

    private var placeholder: String {
        if let project = session.activeProject {
            return project.codeFolder != nil ? "Ask about \(project.name)" : "Message \(project.name)"
        }
        return "Ask anything · / for skills · @ for tools"
    }

    /// Chats other than the one on screen that are still receiving a reply.
    private var backgroundStreams: Int {
        session.streamingIDs.subtracting([session.activeID].compactMap { $0 }).count
    }

    private var backgroundPill: some View {
        HStack(spacing: 5) {
            CueOrb(size: 14, energy: 1)
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
                .contentShape(Rectangle())
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
                .contentShape(Rectangle())
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
