import AppKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case provider
    case projects
    case skills
    case listen
    case hotkeys
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: "AI provider"
        case .projects: "Projects"
        case .skills: "Skills"
        case .listen: "Interview listen"
        case .hotkeys: "Hotkeys"
        case .data: "Data controls"
        }
    }

    var symbol: String {
        switch self {
        case .provider: "key.fill"
        case .projects: "folder"
        case .skills: "sparkles"
        case .listen: "waveform"
        case .hotkeys: "keyboard"
        case .data: "lock.shield"
        }
    }
}

struct SettingsView: View {
    @Bindable var session: AppSession
    @State private var section: SettingsSection = .provider
    @State private var apiKey = ""
    @State private var draft = PublicSettings.default
    @State private var saveError: String?
    @State private var clearKey = false
    @State private var replacingKey = false
    @State private var recording: HotkeyAction?
    @State private var recorder = HotkeyRecordingController()
    @State private var resolvedCodex: CodexBinary?

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { session.settingsOpen = false }

            VStack(spacing: 0) {
                header
                Divider().opacity(0.12)
                HStack(alignment: .top, spacing: 0) {
                    navigation
                    ScrollView {
                        content
                            .padding(20)
                    }
                }
                Divider().opacity(0.12)
                footer
            }
            .frame(width: 760, height: 560)
            .cueGlass(cornerRadius: 28, interactive: true)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        }
        .onAppear {
            draft = session.settings
            resolvedCodex = CodexBinaryLocator.resolve(override: draft.codexPath)
            apiKey = ""
            clearKey = false
            replacingKey = false
            saveError = nil
            stopRecording(restoreHotkeys: false)
        }
        .onDisappear {
            stopRecording(restoreHotkeys: true)
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button {
                session.settingsOpen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .cueGlass(cornerRadius: 14, interactive: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { item in
                Button {
                    if item != .hotkeys {
                        stopRecording(restoreHotkeys: true)
                    }
                    section = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            if section == item {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.16))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 200)
        .background(.white.opacity(0.06))
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .provider: provider
        case .projects: projectsSection
        case .skills: skillsSection
        case .listen: listen
        case .hotkeys: hotkeys
        case .data: data
        }
    }

    private var provider: some View {
        VStack(alignment: .leading, spacing: 14) {
            CueGlassField(
                title: "OpenAI API key",
                help: "Stored in the macOS Keychain and a locked file in Application Support. Rebuilds in Xcode keep the key."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let hint = session.settings.keyHint, apiKey.isEmpty, !clearKey, !replacingKey {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("Saved on this Mac · \(hint)")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button("Replace") { replacingKey = true }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                            Button("Remove") { clearKey = true }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    if session.settings.keyHint == nil || !apiKey.isEmpty || clearKey || replacingKey {
                        CueLiveSecureField(text: $apiKey, placeholder: "sk-…")
                            .frame(height: 22)
                    }
                }
            }

            CueGlassField(title: "Model") {
                HStack {
                    Picker("Model", selection: $draft.model) {
                        ForEach(ModelCatalog.models) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Spacer()
                    Picker("Thinking", selection: $draft.reasoningEffort) {
                        ForEach(ModelCatalog.definition(for: draft.model).supportedEfforts, id: \.self) { effort in
                            Text(ModelCatalog.definition(for: effort).label).tag(effort)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            CueGlassToggle(title: "Web search", subtitle: "Let the model verify time-sensitive facts.", isOn: $draft.webSearchEnabled)

            CueGlassField(title: "System instruction") {
                TextEditor(text: $draft.systemInstruction)
                    .font(.system(size: 13))
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
            }
        }
    }

    private var skillsSection: some View {
        let library = session.skills
        let folder = library.globalRoot.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return VStack(alignment: .leading, spacing: 14) {
            CueGlassField(
                title: "Skill library",
                help: "Skills are Markdown prompts you invoke by typing / in the composer. Each is `name.md` or `name/SKILL.md`, optionally starting with a front-matter block that sets `name:` and `description:`. Project chats also load `.cue/skills` and `.claude/skills` from the code folder."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(folder)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Open folder") { NSWorkspace.shared.activateFileViewerSelecting([library.globalRoot]) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                        Button("Reload") { session.refreshSkills() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("""
                    ---
                    name: review
                    description: Review a diff for bugs and risky changes
                    ---
                    You are a careful reviewer. For the request below…
                    """)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            CueGlassField(title: "Loaded skills") {
                VStack(alignment: .leading, spacing: 8) {
                    if library.skills.isEmpty {
                        Text("No skills yet. Add a Markdown file to \(folder) and it appears here.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.skills) { skill in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                                .frame(width: 18)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("/\(skill.name)")
                                        .font(.system(size: 13, weight: .medium))
                                    if skill.scope == .project {
                                        Text("project")
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                if !skill.description.isEmpty {
                                    Text(skill.description)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text(skill.sourcePath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.sourcePath)])
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            CueGlassField(
                title: "Codex CLI",
                help: "Project chats run the OpenAI Codex CLI in read-only mode inside the folder you open. Leave blank to auto-detect (PATH, Homebrew, npm, or Halo.app)."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Auto-detect", text: Binding(
                            get: { draft.codexPath ?? "" },
                            set: { draft.codexPath = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .onSubmit { resolvedCodex = CodexBinaryLocator.resolve(override: draft.codexPath) }
                        Button("Choose…") { chooseCodexBinary() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                        Button("Check") { resolvedCodex = CodexBinaryLocator.resolve(override: draft.codexPath) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    if let resolvedCodex {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Found via \(resolvedCodex.source)")
                                    .font(.system(size: 12, weight: .medium))
                                Text(resolvedCodex.executable)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(resolvedCodex.executable)
                            }
                        }
                    } else {
                        Label("No Codex CLI found. Install with `npm i -g @openai/codex` or choose the binary.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }
            }

            CueGlassField(title: "Projects", help: "Projects group chats and give them shared instructions and knowledge files. Link a code folder to run a project's chats through Codex inside it.") {
                VStack(alignment: .leading, spacing: 8) {
                    if session.projects.isEmpty {
                        Text("No projects yet. Use “New project” in the sidebar.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.projects, id: \.identifier) { project in
                        HStack(spacing: 10) {
                            WorkspaceAvatar(letter: ProjectPaths.avatarLetter(project.name), isProject: true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(project.codeFolder ?? "No code folder · \(project.knowledge.count) knowledge file\(project.knowledge.count == 1 ? "" : "s")")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if project.codeFolder != nil {
                                Text(project.catalog == nil ? "Not indexed" : "Indexed")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Button("Re-index") {
                                    session.indexPrompt = project
                                    session.settingsOpen = false
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                            }
                            Button("Edit") {
                                session.projectSettingsID = project.identifier
                                session.settingsOpen = false
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            Button("Remove") { session.removeProject(project) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func chooseCodexBinary() {
        let dialog = NSOpenPanel()
        dialog.title = "Choose the codex executable"
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        dialog.showsHiddenFiles = true
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        draft.codexPath = url.path
        resolvedCodex = CodexBinaryLocator.resolve(override: url.path)
    }

    private var listen: some View {
        VStack(alignment: .leading, spacing: 14) {
            CueGlassField(title: "Listen mode", help: draft.listenMode.help) {
                Picker("Listen mode", selection: $draft.listenMode) {
                    ForEach(ListenMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            CueGlassField(title: "Whisper model") {
                Picker("Whisper", selection: $draft.whisperModel) {
                    ForEach(WhisperModelID.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            CueGlassToggle(
                title: "Audio auto mode",
                subtitle: "Segment speaker audio with VAD. Off means hotkey-only capture.",
                isOn: $draft.audioAutoMode
            )
            if draft.listenMode == .accessibility {
                CueGlassField(title: "Accessibility") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AccessibilityTrust.isTrusted
                             ? "Accessibility is granted. Enable Live Captions in System Settings."
                             : "Cue needs Accessibility plus Live Captions.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Request Accessibility") { AccessibilityTrust.request() }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var hotkeys: some View {
        VStack(alignment: .leading, spacing: 14) {
            CueGlassToggle(title: "Passive focus", subtitle: "Show Cue without stealing keyboard focus.", isOn: $draft.passiveFocusMode)
            CueGlassToggle(title: "Always on top", isOn: $draft.alwaysOnTop)
            CueGlassField(title: "Opacity") {
                Slider(value: $draft.windowOpacity, in: 0.15...1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Global hotkeys")
                    .font(.system(size: 13, weight: .semibold))
                Text("Click a shortcut, then press the new combination. Esc cancels.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            ForEach(HotkeyGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(HotkeyCatalog.items(in: group).enumerated()), id: \.element.id) { index, item in
                            hotkeyRow(item)
                            if index < HotkeyCatalog.items(in: group).count - 1 {
                                Divider().opacity(0.12)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .cueGlass(cornerRadius: 18, interactive: true)
                }
            }

            Button("Reset defaults") {
                draft.setHotkeys(HotkeyCatalog.defaults)
                stopRecording(restoreHotkeys: true)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private func hotkeyRow(_ item: HotkeyDefinition) -> some View {
        let accelerator = draft.hotkeyMap[item.id] ?? HotkeyCatalog.defaults[item.id] ?? ""
        let isCustom = accelerator != (HotkeyCatalog.defaults[item.id] ?? "")
        let conflict = HotkeyCatalog.conflict(for: item.id, in: draft.hotkeyMap)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                Text(item.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isCustom {
                Button {
                    assign(HotkeyCatalog.defaults[item.id] ?? accelerator, to: item.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Restore default")
            }
            HotkeyChip(
                accelerator: accelerator,
                isRecording: recording == item.id,
                conflict: conflict?.label,
                onRecord: {
                    if recording == item.id {
                        stopRecording(restoreHotkeys: true)
                    } else {
                        beginRecording(item.id)
                    }
                }
            )
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label), \(HotkeyFormat.displayLabel(for: accelerator))")
        .accessibilityHint("Click the shortcut to record a new key combination")
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: 14) {
            CueGlassToggle(
                title: "Stealth mode",
                subtitle: "Exclude Cue from screen capture APIs.",
                isOn: $draft.stealthMode
            )
            CueGlassField(title: "Chat data") {
                HStack {
                    Button("Copy current chat") { exportActive() }
                        .buttonStyle(.plain)
                    Spacer()
                    Button("Delete all chats") {
                        for conversation in session.conversations {
                            session.deleteConversation(conversation)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let saveError {
                Text(saveError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { session.settingsOpen = false }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .cueGlass(cornerRadius: 16, interactive: true)
            Button("Save") { save() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: Capsule())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func save() {
        stopRecording(restoreHotkeys: false)
        NSApp.keyWindow?.makeFirstResponder(nil)
        saveError = nil
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try session.saveSettings(
                draft,
                apiKey: trimmed.isEmpty ? nil : trimmed,
                clearAPIKey: clearKey && trimmed.isEmpty
            )
            session.settingsOpen = false
        } catch {
            saveError = error.localizedDescription
            session.hotkeys.register(session.settings.hotkeyMap)
        }
    }

    private func beginRecording(_ action: HotkeyAction) {
        let draftBinding = $draft
        let recordingBinding = $recording
        let session = session
        session.hotkeys.unregister()
        recording = action
        recorder.start(action) { action, accelerator in
            var map = draftBinding.wrappedValue.hotkeyMap
            map[action] = accelerator
            draftBinding.wrappedValue.setHotkeys(map)
            recordingBinding.wrappedValue = nil
            session.hotkeys.register(session.settings.hotkeyMap)
        } cancel: {
            recordingBinding.wrappedValue = nil
            session.hotkeys.register(session.settings.hotkeyMap)
        }
    }

    private func stopRecording(restoreHotkeys: Bool) {
        recorder.stop()
        recording = nil
        if restoreHotkeys {
            session.hotkeys.register(session.settings.hotkeyMap)
        }
    }

    private func assign(_ accelerator: String, to action: HotkeyAction) {
        var map = draft.hotkeyMap
        map[action] = accelerator
        draft.setHotkeys(map)
    }

    private func exportActive() {
        let text = session.activeTurns.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
