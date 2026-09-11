import AppKit
import Foundation
import SwiftData
import SwiftUI

/// One in-flight assistant turn. Several can run at once, one per conversation.
@MainActor
private final class ChatRequest {
    let conversationID: UUID
    let assistantID: UUID
    let token = CancellationToken()
    var task: Task<Void, Never>?

    init(conversationID: UUID, assistantID: UUID) {
        self.conversationID = conversationID
        self.assistantID = assistantID
    }
}

@MainActor
@Observable
final class AppSession {
    let container: ModelContainer
    let settingsStore: SettingsStore
    let listen = ListenController()
    let remote = RemoteControlSession()
    let hotkeys = GlobalHotkeyCenter()
    private let client = ResponsesClient()
    private let codex = CodexClient()

    var panel: CuePanelController?
    var conversations: [Conversation] = []
    var projects: [Project] = []
    var activeID: UUID?
    var draft = ""
    var attachments: [MessageAttachment] = []
    var sidebarOpen = true
    var settingsOpen = false
    var searchOpen = false
    var previewAttachment: MessageAttachment?
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

    var activeTurns: [ChatTurn] {
        (activeConversation?.messages ?? []).sorted { $0.createdAt < $1.createdAt }.map { $0.asTurn() }
    }

    /// True while the on-screen conversation is streaming. Other chats may stream in the background.
    var isStreaming: Bool {
        guard let activeID else { return false }
        return streamingIDs.contains(activeID)
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

    // MARK: - Conversations

    func newChat() {
        let conversation = Conversation(projectID: nil)
        container.mainContext.insert(conversation)
        save()
        reloadConversations()
        select(conversation.identifier)
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
    }

    func openProjectFolder() {
        let dialog = NSOpenPanel()
        dialog.title = "Open project folder"
        dialog.message = "This chat will read the folder through Codex. Other chats stay as regular conversations."
        dialog.canChooseDirectories = true
        dialog.canChooseFiles = false
        dialog.allowsMultipleSelection = false
        dialog.canCreateDirectories = false
        dialog.prompt = "Open"
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        do {
            let resolved = try ProjectPaths.usableDirectory(url.path)
            let project = upsertProject(path: resolved, name: url.lastPathComponent)
            if activeConversation == nil { newChat() }
            guard let conversation = activeConversation else { return }
            attachProject(project, to: conversation)
            indexError = nil
            indexing = false
            indexPrompt = project
        } catch {
            remoteNotice = error.localizedDescription
        }
    }

    @discardableResult
    private func upsertProject(path: String, name: String) -> Project {
        if let existing = projects.first(where: { $0.folderPath == path }) {
            existing.name = name.isEmpty ? existing.name : name
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
        container.mainContext.delete(project)
        save()
        reloadProjects()
        reloadConversations()
    }

    func skipProjectIndex() {
        guard !indexing else { return }
        indexPrompt = nil
        indexError = nil
    }

    func confirmProjectIndex() {
        guard let project = indexPrompt, !indexing else { return }
        indexing = true
        indexError = nil
        let root = project.folderPath
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

    /// Sends the draft in the active conversation, or stops that conversation's turn if one is running.
    func send() {
        guard let activeID else { return }
        if streamingIDs.contains(activeID) {
            stop(conversationID: activeID)
            return
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
                    apply(event, request: request)
                }
            } catch {
                apply(.error(error.localizedDescription), request: request)
            }
            finish(conversationID: conversationID, request: request)
        }
    }

    func stop(conversationID: UUID) {
        guard let request = requests[conversationID] else { return }
        request.token.cancel()
        request.task?.cancel()
    }

    private func makeStream(
        for conversation: Conversation,
        history: [ChatTurn],
        apiKey: String,
        token: CancellationToken
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let snapshot = settings
        if let project = project(for: conversation) {
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
                projectPath: project.folderPath,
                threadID: conversation.codexThreadID,
                prompt: CodexPrompt.build(messages: messages, catalog: project.catalog)
            )
            return codex.stream(request, signal: token)
        }
        let continuation = ChatContinuationBuilder.build(from: history)
        return client.stream(apiKey: apiKey, settings: snapshot, continuation: continuation, signal: token)
    }

    private func finish(conversationID: UUID, request: ChatRequest) {
        guard requests[conversationID] === request else { return }
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

    private func apply(_ event: ChatStreamEvent, request: ChatRequest) {
        guard let conversation = conversations.first(where: { $0.identifier == request.conversationID }),
              let message = conversation.messages.first(where: { $0.identifier == request.assistantID })
        else { return }
        switch event {
        case .start:
            break
        case .status(let text):
            if message.content.isEmpty {
                activities[conversation.identifier] = text
            }
        case .delta(let delta):
            message.content += delta
            activities[conversation.identifier] = nil
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
        save()
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
