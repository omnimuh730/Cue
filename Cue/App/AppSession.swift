import AppKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// One in-flight assistant turn. Several can run at once, one per conversation.
@MainActor
private final class ChatRequest {
    let conversationID: UUID
    let assistantID: UUID
    let token = CancellationToken()
    var task: Task<Void, Never>?
    /// Deltas received since the last UI flush. Tokens arrive far faster than 25 fps is useful,
    /// and each model write re-renders the bubble, so they are batched.
    var pendingText = ""
    var flushScheduled = false
    var lastSaveAt = Date.distantPast

    init(conversationID: UUID, assistantID: UUID) {
        self.conversationID = conversationID
        self.assistantID = assistantID
    }
}

/// Batching cadence for streamed text and the floor between SQLite commits while streaming.
private enum StreamPacing {
    static let flushInterval: Duration = .milliseconds(40)
    static let saveInterval: TimeInterval = 1.0
}

@MainActor
@Observable
final class AppSession {
    let container: ModelContainer
    let settingsStore: SettingsStore
    let listen = ListenController()
    let remote = RemoteControlSession()
    let hotkeys = GlobalHotkeyCenter()
    let skills = SkillLibrary()
    private let client = ResponsesClient()
    private let codex = CodexClient()

    var panel: CuePanelController?
    var conversations: [Conversation] = []
    var projects: [Project] = []
    var activeID: UUID?
    var draft = ""
    var attachments: [MessageAttachment] = []
    var sidebarOpen = true
    /// True when the window is too narrow to sit the sidebar beside the chat, so it floats over it.
    private(set) var sidebarOverlaid = false
    /// What the sidebar was doing in the wide layout, restored when the window widens again.
    private var sidebarOpenWhenSplit = true
    var settingsOpen = false
    var searchOpen = false
    var previewAttachment: MessageAttachment?
    /// Mermaid source shown across the window by the diagram preview overlay.
    var previewDiagram: String?
    /// Files still being read for the composer; each shows a placeholder chip.
    private(set) var importingNames: [String] = []
    /// Conversation whose thread info sheet is open.
    var infoConversationID: UUID?
    var mermaidAsCode = false
    var remoteNotice: String?

    /// Conversations with a turn in flight. Drives sidebar and composer state.
    private(set) var streamingIDs: Set<UUID> = []
    /// Latest agent progress line per streaming conversation (Codex explore status).
    private(set) var activities: [UUID: String] = [:]
    /// Conversations that finished a turn while another chat was on screen.
    private(set) var unreadIDs: Set<UUID> = []

    /// Project index prompt shown after opening a folder.
    var indexPrompt: Project?
    var indexing = false
    var indexError: String?
    /// Sidebar workspace filter: nil shows every chat, otherwise only that project's chats.
    var selectedProjectID: UUID?
    /// Project whose settings overlay (instructions, knowledge, folder) is open.
    var projectSettingsID: UUID?
    /// "New project" name prompt.
    var newProjectPromptOpen = false
    /// Knowledge files still being read for a project settings sheet.
    private(set) var importingKnowledge: [String] = []

    private var requests: [UUID: ChatRequest] = [:]
    private var lastCaptionDraft = ""
    /// Composer state parked per conversation so switching chats mid-typing loses nothing.
    private var parkedDrafts: [UUID: (draft: String, attachments: [MessageAttachment])] = [:]

    var settings: PublicSettings { settingsStore.settings }

    var activeConversation: Conversation? {
        conversations.first { $0.identifier == activeID }
    }

    var activeProject: Project? {
        guard let conversation = activeConversation else { return nil }
        return project(for: conversation)
    }

    var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.identifier == selectedProjectID }
    }

    /// Conversations shown in the sidebar for the selected workspace.
    var visibleConversations: [Conversation] {
        guard let selectedProjectID else { return conversations }
        return conversations.filter { $0.projectID == selectedProjectID }
    }

    /// Full decoded turns; used for export and search, not for rendering (decoding attachments is slow).
    var activeTurns: [ChatTurn] {
        activeMessages.map { $0.asTurn() }
    }

    /// Ordered model objects for the chat list. Views observe each `Message` directly so a
    /// streaming delta re-renders one bubble instead of the whole thread.
    var activeMessages: [Message] {
        (activeConversation?.messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// True while the on-screen conversation is streaming. Other chats may stream in the background.
    var isStreaming: Bool {
        guard let activeID else { return false }
        return streamingIDs.contains(activeID)
    }

    var hasComposerPayload: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    /// Stop while a reply is live and the composer is empty; otherwise send (interrupting if needed).
    var composerPrimaryAction: ComposerPrimaryAction {
        .resolve(isStreaming: isStreaming, hasPayload: hasComposerPayload)
    }

    var activeActivity: String? {
        activeID.flatMap { activities[$0] }
    }

    func isStreaming(_ conversation: Conversation) -> Bool {
        streamingIDs.contains(conversation.identifier)
    }

    func activity(for conversation: Conversation) -> String? {
        activities[conversation.identifier]
    }

    func isUnread(_ conversation: Conversation) -> Bool {
        unreadIDs.contains(conversation.identifier)
    }

    func project(for conversation: Conversation) -> Project? {
        guard let id = conversation.projectID else { return nil }
        return projects.first { $0.identifier == id }
    }

    init(container: ModelContainer, settingsStore: SettingsStore) {
        self.container = container
        self.settingsStore = settingsStore
        reloadProjects()
        reloadConversations()
        listen.configure(settings: settingsStore.settings)
        listen.onTranscript = { [weak self] text in
            self?.appendDraft(text)
        }
        listen.onCaptionLines = { [weak self] lines in
            self?.applyCaptionLines(lines)
        }
        listen.onStatus = { _ in }
        remote.onHotkey = { [weak self] action in
            self?.handle(action)
        }
        remote.onText = { [weak self] text in
            self?.applyRemoteText(text)
        }
        remote.onImage = { [weak self] attachment in
            self?.attachments.append(attachment)
        }
    }

    func attach(panel: CuePanelController) {
        self.panel = panel
        applyWindowChrome()
        hotkeys.onAction = { [weak self] action in
            self?.handle(action)
        }
        hotkeys.register(settings.hotkeyMap)
        remote.updateHotkeys(settings.hotkeyMap)
        if activeConversation == nil {
            if let first = conversations.first {
                activeID = first.identifier
            } else {
                newChat()
            }
        }
    }

    // MARK: - Persistence

    func reloadConversations() {
        let descriptor = FetchDescriptor<Conversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        conversations = (try? container.mainContext.fetch(descriptor)) ?? []
        if activeID == nil {
            activeID = conversations.first?.identifier
        }
        // Interrupted turns from a previous launch must not look live forever.
        for conversation in conversations where !streamingIDs.contains(conversation.identifier) {
            for message in conversation.messages where message.status == .streaming {
                message.statusRaw = MessageStatus.error.rawValue
                if message.content.isEmpty { message.content = "Response interrupted." }
            }
        }
    }

    func reloadProjects() {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        projects = (try? container.mainContext.fetch(descriptor)) ?? []
    }

    private func save() {
        try? container.mainContext.save()
    }

    func applyWindowChrome() {
        panel?.apply(settings: settings, remoteActive: remote.active)
    }

    func saveSettings(_ next: PublicSettings, apiKey: String? = nil, clearAPIKey: Bool = false) throws {
        try settingsStore.save(next, apiKey: apiKey, clearAPIKey: clearAPIKey)
        listen.configure(settings: settingsStore.settings)
        hotkeys.register(settings.hotkeyMap)
        remote.updateHotkeys(settings.hotkeyMap)
        applyWindowChrome()
    }

    /// Switches the sidebar between sitting beside the chat and floating over it. A floating
    /// sidebar covers the transcript, so it starts closed and the user opens it deliberately.
    func setSidebarOverlaid(_ value: Bool) {
        guard sidebarOverlaid != value else { return }
        sidebarOverlaid = value
        if value {
            sidebarOpenWhenSplit = sidebarOpen
            sidebarOpen = false
        } else {
            sidebarOpen = sidebarOpenWhenSplit
        }
    }

    /// Dismisses a floating sidebar after it has been used; a docked one stays put.
    func dismissSidebarIfOverlaid() {
        if sidebarOverlaid { sidebarOpen = false }
    }

    // MARK: - Conversations

    /// New chat in the selected workspace (or Personal when no project is selected).
    func newChat() {
        newChat(in: selectedProjectID)
    }

    func newChat(in projectID: UUID?) {
        // Pressing "New chat" from an empty chat should stay put rather than stack up blank
        // threads the user then has to delete. Staying put also keeps whatever is half-typed.
        if let active = activeConversation, isBlank(active), active.projectID == projectID { return }
        if let blank = blankConversation(in: projectID) {
            select(blank.identifier)
            return
        }
        let conversation = Conversation(projectID: projectID)
        container.mainContext.insert(conversation)
        save()
        reloadConversations()
        select(conversation.identifier)
    }

    /// A chat with no turns in it and nothing in flight.
    private func isBlank(_ conversation: Conversation) -> Bool {
        conversation.messages.isEmpty && !streamingIDs.contains(conversation.identifier)
    }

    /// An existing chat in this workspace that has nothing in it yet.
    private func blankConversation(in projectID: UUID?) -> Conversation? {
        conversations.first { $0.projectID == projectID && isBlank($0) }
    }

    /// Switches the sidebar workspace and lands on that workspace's newest chat.
    func selectWorkspace(_ projectID: UUID?) {
        selectedProjectID = projectID
        if let first = visibleConversations.first {
            select(first.identifier)
        } else {
            newChat(in: projectID)
        }
    }

    func select(_ conversationID: UUID) {
        guard conversations.contains(where: { $0.identifier == conversationID }) else { return }
        if let previous = activeID, previous != conversationID {
            if draft.isEmpty, attachments.isEmpty {
                parkedDrafts[previous] = nil
            } else {
                parkedDrafts[previous] = (draft, attachments)
            }
        }
        activeID = conversationID
        unreadIDs.remove(conversationID)
        let parked = parkedDrafts.removeValue(forKey: conversationID)
        draft = parked?.draft ?? ""
        attachments = parked?.attachments ?? []
        lastCaptionDraft = ""
        refreshSkills()
    }

    // MARK: - Skills

    /// Rescans skill folders for the active workspace; project chats add their repo's skills.
    func refreshSkills() {
        let folder = activeProject?.codeFolder
        if skills.projectFolder != folder {
            skills.reload(projectFolder: folder)
        } else {
            skills.reload()
        }
    }

    /// Attaches the skill as a chip and clears the `/query` token so the user can type the request.
    func attachSkill(_ skill: SkillDefinition) {
        if let query = SkillInvocation.query(in: draft) {
            draft = String(draft.dropFirst(query.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        attachments.removeAll { $0.kind == .skill && $0.name == skill.name }
        attachments.append(SkillInvocation.attachment(for: skill))
    }

    func deleteConversation(_ conversation: Conversation) {
        stop(conversationID: conversation.identifier)
        container.mainContext.delete(conversation)
        save()
        if activeID == conversation.identifier {
            activeID = nil
        }
        unreadIDs.remove(conversation.identifier)
        parkedDrafts[conversation.identifier] = nil
        if infoConversationID == conversation.identifier { infoConversationID = nil }
        reloadConversations()
        if activeID == nil {
            if let first = conversations.first {
                select(first.identifier)
            } else {
                newChat()
            }
        }
    }

    // MARK: - Projects

    func attachProject(_ project: Project, to conversation: Conversation) {
        conversation.projectID = project.identifier
        conversation.codexThreadID = nil
        conversation.updatedAt = .now
        save()
        reloadConversations()
        refreshSkills()
    }

    /// Creates an empty project (instructions and knowledge come later) and opens its settings.
    @discardableResult
    func createProject(name: String) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: trimmed.isEmpty ? "New project" : trimmed)
        container.mainContext.insert(project)
        save()
        reloadProjects()
        selectWorkspace(project.identifier)
        projectSettingsID = project.identifier
        return project
    }

    func renameProject(_ project: Project, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.name else { return }
        project.name = trimmed
        project.updatedAt = .now
        save()
        reloadProjects()
    }

    func setProjectInstructions(_ project: Project, _ text: String) {
        let clipped = String(text.prefix(ProjectContext.maxInstructionCharacters))
        project.instructions = clipped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clipped
        project.updatedAt = .now
        save()
    }

    /// Picks a code folder and links it to the project; that project's chats then run through Codex.
    func openProjectFolder(for project: Project? = nil) {
        let dialog = NSOpenPanel()
        dialog.title = "Open project folder"
        dialog.message = project.map { "Chats in \($0.name) will read this folder through Codex." }
            ?? "A new project will read this folder through Codex."
        dialog.canChooseDirectories = true
        dialog.canChooseFiles = false
        dialog.allowsMultipleSelection = false
        dialog.canCreateDirectories = false
        dialog.prompt = "Open"
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        do {
            let resolved = try ProjectPaths.usableDirectory(url.path)
            let target = project ?? upsertProject(path: resolved, name: url.lastPathComponent)
            if target.folderPath != resolved {
                target.folderPath = resolved
                target.catalog = nil
                target.catalogAt = nil
                target.updatedAt = .now
                // The Codex thread was rooted in the old folder; start fresh.
                for conversation in conversations where conversation.projectID == target.identifier {
                    conversation.codexThreadID = nil
                }
                save()
                reloadProjects()
                reloadConversations()
            }
            if selectedProjectID != target.identifier {
                selectWorkspace(target.identifier)
            }
            refreshSkills()
            indexError = nil
            indexing = false
            indexPrompt = target
        } catch {
            remoteNotice = error.localizedDescription
        }
    }

    func unlinkProjectFolder(_ project: Project) {
        guard project.codeFolder != nil else { return }
        project.folderPath = ""
        project.catalog = nil
        project.catalogAt = nil
        project.updatedAt = .now
        for conversation in conversations where conversation.projectID == project.identifier {
            conversation.codexThreadID = nil
        }
        save()
        reloadProjects()
        reloadConversations()
        refreshSkills()
    }

    @discardableResult
    private func upsertProject(path: String, name: String) -> Project {
        if let existing = projects.first(where: { $0.folderPath == path }) {
            existing.updatedAt = .now
            save()
            reloadProjects()
            return existing
        }
        let project = Project(name: name.isEmpty ? "Project" : name, folderPath: path)
        container.mainContext.insert(project)
        save()
        reloadProjects()
        return project
    }

    func removeProject(_ project: Project) {
        for conversation in conversations where conversation.projectID == project.identifier {
            conversation.projectID = nil
            conversation.codexThreadID = nil
        }
        if selectedProjectID == project.identifier { selectedProjectID = nil }
        if projectSettingsID == project.identifier { projectSettingsID = nil }
        if indexPrompt?.identifier == project.identifier { indexPrompt = nil }
        container.mainContext.delete(project)
        save()
        reloadProjects()
        reloadConversations()
        refreshSkills()
    }

    // MARK: Knowledge files

    func pickKnowledgeFiles(for project: Project) {
        let dialog = NSOpenPanel()
        dialog.title = "Add knowledge"
        dialog.message = "Documents added here are sent with every chat in \(project.name). PDFs are stored as extracted text."
        dialog.canChooseDirectories = false
        dialog.canChooseFiles = true
        dialog.allowsMultipleSelection = true
        dialog.allowedContentTypes = FileAttachmentImporter.allowedContentTypes.filter { !$0.conforms(to: .image) }
        dialog.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .OK else { return }
        addKnowledge(dialog.urls, to: project)
    }

    func addKnowledge(_ urls: [URL], to project: Project) {
        let projectID = project.identifier
        for url in urls {
            let name = url.lastPathComponent
            importingKnowledge.append(name)
            Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> Result<MessageAttachment, Error> in
                    Result { try FileAttachmentImporter.load(url) }
                }.value
                guard let self else { return }
                if let index = importingKnowledge.firstIndex(of: name) { importingKnowledge.remove(at: index) }
                guard let target = projects.first(where: { $0.identifier == projectID }) else { return }
                switch result {
                case .success(let attachment):
                    guard let entry = ProjectContext.knowledgeEntry(from: attachment) else {
                        remoteNotice = "\(name) has no text to add as knowledge."
                        return
                    }
                    var knowledge = target.knowledge.filter { $0.name != entry.name }
                    let total = knowledge.reduce(0) { $0 + ($1.text?.count ?? 0) } + (entry.text?.count ?? 0)
                    guard total <= ProjectContext.maxKnowledgeCharacters else {
                        remoteNotice = "\(name) would push \(target.name)'s knowledge past its size limit."
                        return
                    }
                    knowledge.append(entry)
                    target.knowledge = knowledge
                    target.updatedAt = .now
                    save()
                case .failure(let error):
                    remoteNotice = error.localizedDescription
                }
            }
        }
    }

    func removeKnowledge(_ attachmentID: String, from project: Project) {
        project.knowledge = project.knowledge.filter { $0.id != attachmentID }
        project.updatedAt = .now
        save()
    }

    func skipProjectIndex() {
        guard !indexing else { return }
        indexPrompt = nil
        indexError = nil
    }

    func confirmProjectIndex() {
        guard let project = indexPrompt, let root = project.codeFolder, !indexing else { return }
        indexing = true
        indexError = nil
        let projectID = project.identifier
        Task {
            let catalog = await Task.detached(priority: .userInitiated) { ProjectCatalog.build(root: root) }.value
            if let target = projects.first(where: { $0.identifier == projectID }) {
                target.catalog = catalog
                target.catalogAt = .now
                target.updatedAt = .now
                save()
                reloadProjects()
            }
            indexing = false
            indexPrompt = nil
        }
    }

    // MARK: - Sending

    /// Sends the draft, interrupting any in-flight turn in this conversation first.
    /// An empty composer while streaming only stops; it never waits for the current reply to finish.
    func send() {
        guard let activeID else { return }
        if streamingIDs.contains(activeID) {
            stop(conversationID: activeID)
            if !hasComposerPayload { return }
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard let apiKey = APIKeyStore.load() else {
            settingsOpen = true
            return
        }
        if activeConversation == nil { newChat() }
        guard let conversation = activeConversation else { return }

        let user = ChatTurn(
            id: UUID(),
            role: .user,
            content: text,
            createdAt: .now,
            status: .complete,
            attachments: attachments
        )
        insert(user, into: conversation)
        if conversation.title == "New chat" {
            conversation.title = String(text.prefix(48)).ifEmpty("New chat")
        }
        draft = ""
        lastCaptionDraft = ""
        attachments = []
        listen.resetAfterSend()

        let assistantID = UUID()
        let assistant = ChatTurn(
            id: assistantID,
            role: .assistant,
            content: "",
            createdAt: .now,
            status: .streaming,
            attachments: []
        )
        // Mark the conversation live before the placeholder lands, or the reload in `insert`
        // would treat the new streaming message as an interrupted turn.
        let request = ChatRequest(conversationID: conversation.identifier, assistantID: assistantID)
        requests[conversation.identifier] = request
        streamingIDs.insert(conversation.identifier)
        activities[conversation.identifier] = nil
        insert(assistant, into: conversation)

        let history = conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.asTurn() }
            .filter { $0.id != assistantID }
        let stream = makeStream(for: conversation, history: history, apiKey: apiKey, token: request.token)
        let conversationID = conversation.identifier
        request.task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    if Task.isCancelled || request.token.isCancelled { break }
                    apply(event, request: request)
                }
            } catch is CancellationError {
                // `stop` already finalized this turn so a follow-up could start immediately.
            } catch {
                apply(.error(error.localizedDescription), request: request)
            }
            finish(conversationID: conversationID, request: request)
        }
    }

    /// Cancels the in-flight turn immediately: tokens, process, and UI state. Does not wait for
    /// remaining SSE/Codex output or for the bubble to finish animating.
    func stop(conversationID: UUID) {
        guard let request = requests[conversationID] else { return }
        request.token.cancel()
        request.task?.cancel()
        flush(request, force: true)
        if let (_, message) = target(for: request), message.status == .streaming {
            message.statusRaw = MessageStatus.complete.rawValue
            if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message.content = "Response interrupted."
            }
        }
        requests[conversationID] = nil
        streamingIDs.remove(conversationID)
        activities[conversationID] = nil
        save()
    }

    private func makeStream(
        for conversation: Conversation,
        history: [ChatTurn],
        apiKey: String,
        token: CancellationToken
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let snapshot = settings
        let project = project(for: conversation)
        if let project, let folder = project.codeFolder {
            guard let binary = CodexBinaryLocator.resolve(override: snapshot.codexPath) else {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.error(CodexError.missingBinary.localizedDescription))
                    continuation.finish()
                }
            }
            let messages = ChatContinuationBuilder.build(from: history).messages
            let request = CodexTurnRequest(
                binary: binary,
                apiKey: apiKey,
                model: snapshot.model,
                effort: snapshot.reasoningEffort,
                projectPath: folder,
                threadID: conversation.codexThreadID,
                prompt: CodexPrompt.build(messages: messages, catalog: project.catalog, project: project.context),
                images: messages.last { $0.role == .user }?.attachments.filter(\.isImage) ?? []
            )
            return codex.stream(request, signal: token)
        }
        var continuation = ChatContinuationBuilder.build(from: history)
        continuation.promptCacheKey = "cue-\(conversation.identifier.uuidString.lowercased())"
        continuation.project = project.map(\.context)
        return client.stream(apiKey: apiKey, settings: snapshot, continuation: continuation, signal: token)
    }

    private func finish(conversationID: UUID, request: ChatRequest) {
        guard requests[conversationID] === request else { return }
        flush(request, force: true)
        requests[conversationID] = nil
        streamingIDs.remove(conversationID)
        activities[conversationID] = nil
        if conversationID != activeID, conversations.contains(where: { $0.identifier == conversationID }) {
            unreadIDs.insert(conversationID)
        }
    }

    // MARK: - Hotkeys

    func handle(_ action: HotkeyAction) {
        switch action {
        case .toggleShowHide:
            panel?.toggle(passive: settings.passiveFocusMode)
        case .opacityUp:
            let opacity = panel?.adjustOpacity(0.05) ?? settings.windowOpacity
            settingsStore.patch { settings in settings.windowOpacity = opacity }
            applyWindowChrome()
        case .opacityDown:
            let opacity = panel?.adjustOpacity(-0.05) ?? settings.windowOpacity
            settingsStore.patch { settings in settings.windowOpacity = opacity }
            applyWindowChrome()
        case .toggleAlwaysOnTop:
            settingsStore.patch { settings in settings.alwaysOnTop.toggle() }
            applyWindowChrome()
        case .moveWindowLeft:
            panel?.nudge(dx: -WindowBounds.nudgeStep, dy: 0)
        case .moveWindowUp:
            panel?.nudge(dx: 0, dy: WindowBounds.nudgeStep)
        case .moveWindowRight:
            panel?.nudge(dx: WindowBounds.nudgeStep, dy: 0)
        case .moveWindowDown:
            panel?.nudge(dx: 0, dy: -WindowBounds.nudgeStep)
        case .resizeWider:
            panel?.resize(dw: WindowBounds.nudgeStep, dh: 0)
        case .resizeNarrower:
            panel?.resize(dw: -WindowBounds.nudgeStep, dh: 0)
        case .resizeTaller:
            panel?.resize(dw: 0, dh: WindowBounds.nudgeStep)
        case .resizeShorter:
            panel?.resize(dw: 0, dh: -WindowBounds.nudgeStep)
        case .toggleSidebar:
            sidebarOpen.toggle()
        case .toggleRemoteControl:
            guard let panel else { return }
            if !settings.passiveFocusMode {
                remoteNotice = "Turn on Passive focus in Settings before remote control."
                return
            }
            remote.toggle(panel: panel, hotkeys: settings.hotkeyMap)
            if let error = remote.lastError { remoteNotice = error }
        case .quitApp:
            quit()
        case .toggleAudioAuto:
            settingsStore.patch { settings in settings.audioAutoMode.toggle() }
            listen.configure(settings: settings)
        case .listenStartStop:
            Task { await listen.toggleArmed(settings: settings) }
        case .listenOff:
            Task { await listen.listenOff(settings: settings) }
        case .clearAudioCache:
            listen.resetAfterSend()
            lastCaptionDraft = ""
            draft = ""
        case .cycleModel:
            let model = ModelCatalog.nextModel(after: settings.model)
            settingsStore.patch { settings in
                settings.model = model
                settings.reasoningEffort = ModelCatalog.normalizeEffort(settings.reasoningEffort, for: model)
            }
        case .cycleEffort:
            settingsStore.patch { settings in
                settings.reasoningEffort = ModelCatalog.nextEffort(after: settings.reasoningEffort, for: settings.model)
            }
        case .sendMessage:
            send()
        case .newChat:
            newChat()
        case .toggleMermaidMode:
            mermaidAsCode.toggle()
        case .screenshotDesktop:
            Task { await captureDesktop() }
        case .screenshotRegion:
            Task { await captureRegion() }
        }
    }

    func quit() {
        panel?.isQuitting = true
        hotkeys.unregister()
        remote.stop()
        for id in Array(requests.keys) { stop(conversationID: id) }
        NSApp.terminate(nil)
    }

    private func captureDesktop() async {
        guard let panel else { return }
        do {
            let shot = try await ScreenshotService.captureDesktop(excluding: panel.panel)
            attachments.append(MessageAttachment(id: UUID().uuidString, mimeType: shot.mimeType, name: shot.name, dataURL: shot.dataURL))
            panel.reveal(passive: settings.passiveFocusMode)
        } catch {
            remoteNotice = error.localizedDescription
        }
    }

    private func captureRegion() async {
        guard let panel else { return }
        do {
            let shot = try await ScreenshotService.captureRegion(hiding: panel)
            attachments.append(MessageAttachment(id: UUID().uuidString, mimeType: shot.mimeType, name: shot.name, dataURL: shot.dataURL))
        } catch {
            remoteNotice = error.localizedDescription
        }
    }

    // MARK: - File attachments

    /// Opens the file picker and attaches the chosen documents, images, or text files.
    func pickFiles() {
        let dialog = NSOpenPanel()
        dialog.title = "Attach files"
        dialog.message = "PDF, Word, Excel, PowerPoint, images, Markdown, and other text files."
        dialog.canChooseDirectories = false
        dialog.canChooseFiles = true
        dialog.allowsMultipleSelection = true
        dialog.allowedContentTypes = FileAttachmentImporter.allowedContentTypes
        dialog.prompt = "Attach"
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .OK else { return }
        importFiles(dialog.urls)
    }

    /// Reads files off the main actor and appends them to the composer as they finish.
    func importFiles(_ urls: [URL]) {
        let targetID = activeID
        for url in urls {
            let name = url.lastPathComponent
            importingNames.append(name)
            Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> Result<MessageAttachment, Error> in
                    Result { try FileAttachmentImporter.load(url) }
                }.value
                guard let self else { return }
                if let index = importingNames.firstIndex(of: name) { importingNames.remove(at: index) }
                switch result {
                case .success(let attachment):
                    addAttachment(attachment, to: targetID)
                case .failure(let error):
                    remoteNotice = error.localizedDescription
                }
            }
        }
    }

    func addPastedImage(_ image: NSImage, name: String? = nil) {
        guard let dataURL = ImageAttachmentEncoder.jpegDataURL(image, maxDimension: FileAttachmentImporter.maxImageDimension) else { return }
        attachments.append(MessageAttachment(
            mimeType: "image/jpeg",
            name: name ?? "paste-\(Int(Date().timeIntervalSince1970)).jpg",
            dataURL: dataURL
        ))
    }

    /// Anything dragged onto the window: files import as usual, raw image data becomes an image
    /// attachment as if it had been pasted.
    func acceptDrop(_ providers: [NSItemProvider]) {
        Task { [weak self] in
            let payload = await DroppedItems.load(providers)
            guard let self, !payload.isEmpty else { return }
            importFiles(payload.urls)
            for (index, data) in payload.images.enumerated() {
                guard let image = NSImage(data: data) else { continue }
                addPastedImage(image, name: "drop-\(Int(Date().timeIntervalSince1970))-\(index + 1).jpg")
            }
        }
    }

    /// Lands an attachment in the conversation it was picked for, even if the user switched chats meanwhile.
    private func addAttachment(_ attachment: MessageAttachment, to conversationID: UUID?) {
        let existing = conversationID == activeID ? attachments : (conversationID.flatMap { parkedDrafts[$0]?.attachments } ?? [])
        let budget = existing.reduce(0) { $0 + ($1.promptText?.count ?? 0) } + (attachment.promptText?.count ?? 0)
        guard budget <= FileAttachmentImporter.maxMessageTextCharacters else {
            remoteNotice = "\(attachment.name) would push this message past the attachment text limit."
            return
        }
        if conversationID == activeID || conversationID == nil {
            attachments.append(attachment)
        } else if let conversationID {
            let parked = parkedDrafts[conversationID] ?? ("", [])
            parkedDrafts[conversationID] = (parked.draft, parked.attachments + [attachment])
        }
    }

    // MARK: - Draft input

    private func appendDraft(_ text: String) {
        if draft.isEmpty {
            draft = text
        } else {
            draft += " " + text
        }
    }

    private func applyCaptionLines(_ lines: [CaptionLine]) {
        let applied = CaptionDraftSync.apply(snapshot: lines, to: draft, previousSnapshot: lastCaptionDraft)
        draft = applied.draft
        lastCaptionDraft = applied.snapshot
    }

    private func applyRemoteText(_ text: String) {
        RemoteTextEdit.apply(text, to: &draft)
    }

    // MARK: - Stream application

    private func insert(_ turn: ChatTurn, into conversation: Conversation) {
        let message = Message(identifier: turn.id, role: turn.role, content: turn.content, createdAt: turn.createdAt, status: turn.status)
        message.apply(turn)
        message.conversation = conversation
        conversation.messages.append(message)
        conversation.updatedAt = .now
        save()
        reloadConversations()
    }

    private func target(for request: ChatRequest) -> (Conversation, Message)? {
        guard let conversation = conversations.first(where: { $0.identifier == request.conversationID }),
              let message = conversation.messages.first(where: { $0.identifier == request.assistantID })
        else { return nil }
        return (conversation, message)
    }

    /// Moves batched deltas into the model. Saves only when the commit floor has passed or the
    /// caller insists (turn end), so streaming never blocks on disk per token.
    private func flush(_ request: ChatRequest, force: Bool = false) {
        request.flushScheduled = false
        guard force || requests[request.conversationID] === request else { return }
        guard let (conversation, message) = target(for: request) else { return }
        if !request.pendingText.isEmpty {
            message.content += request.pendingText
            request.pendingText = ""
            conversation.updatedAt = .now
        }
        if force || Date().timeIntervalSince(request.lastSaveAt) >= StreamPacing.saveInterval {
            request.lastSaveAt = Date()
            save()
        }
    }

    private func scheduleFlush(_ request: ChatRequest) {
        guard !request.flushScheduled else { return }
        request.flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: StreamPacing.flushInterval)
            self?.flush(request)
        }
    }

    private func apply(_ event: ChatStreamEvent, request: ChatRequest) {
        guard requests[request.conversationID] === request else { return }
        if case .delta(let delta) = event {
            if request.pendingText.isEmpty, let (conversation, _) = target(for: request) {
                activities[conversation.identifier] = nil
            }
            request.pendingText += delta
            scheduleFlush(request)
            return
        }
        // Every other event is a state change; land any buffered text first so ordering holds.
        flush(request, force: false)
        guard let (conversation, message) = target(for: request) else { return }
        switch event {
        case .start, .delta:
            return
        case .status(let text):
            if message.content.isEmpty {
                activities[conversation.identifier] = text
            }
            return
        case .usage(let usage, let costUsd, let model, let effort, let webSearchCalls, _):
            message.usageJSON = try? JSONEncoder().encode(usage)
            message.costUsd = costUsd
            message.modelRaw = model.rawValue
            message.effortRaw = effort.rawValue
            message.webSearchCalls = webSearchCalls
            conversation.totalCostUsd += costUsd
            conversation.totalInputTokens += usage.inputTokens
            conversation.totalOutputTokens += usage.outputTokens
            conversation.totalReasoningTokens += usage.reasoningTokens
            conversation.totalWebSearchCalls += webSearchCalls
        case .done(let timing, let responseID, let codexThreadID):
            message.statusRaw = MessageStatus.complete.rawValue
            message.timingJSON = try? JSONEncoder().encode(timing)
            message.responseID = responseID
            if let codexThreadID, !codexThreadID.isEmpty {
                conversation.codexThreadID = codexThreadID
            }
        case .error(let text):
            message.statusRaw = MessageStatus.error.rawValue
            if message.content.isEmpty {
                message.content = text
            }
        }
        conversation.updatedAt = .now
        request.lastSaveAt = Date()
        save()
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
