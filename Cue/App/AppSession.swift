import AppKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppSession {
    let container: ModelContainer
    let settingsStore: SettingsStore
    let listen = ListenController()
    let remote = RemoteControlSession()
    let hotkeys = GlobalHotkeyCenter()
    private let client = ResponsesClient()

    var panel: CuePanelController?
    var conversations: [Conversation] = []
    var activeID: UUID?
    var draft = ""
    var attachments: [MessageAttachment] = []
    var sidebarOpen = true
    var settingsOpen = false
    var searchOpen = false
    var isStreaming = false
    var mermaidAsCode = false
    var remoteNotice: String?
    private var streamTask: Task<Void, Never>?
    private var cancelToken: CancellationToken?

    var settings: PublicSettings { settingsStore.settings }

    var activeConversation: Conversation? {
        conversations.first { $0.identifier == activeID }
    }

    var activeTurns: [ChatTurn] {
        (activeConversation?.messages ?? []).sorted { $0.createdAt < $1.createdAt }.map { $0.asTurn() }
    }

    init(container: ModelContainer, settingsStore: SettingsStore) {
        self.container = container
        self.settingsStore = settingsStore
        reloadConversations()
        listen.configure(settings: settingsStore.settings)
        listen.onTranscript = { [weak self] text in
            self?.appendDraft(text)
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
        if conversations.isEmpty {
            newChat()
        }
    }

    func reloadConversations() {
        let descriptor = FetchDescriptor<Conversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        conversations = (try? container.mainContext.fetch(descriptor)) ?? []
        if activeID == nil {
            activeID = conversations.first?.identifier
        }
    }

    func applyWindowChrome() {
        panel?.apply(settings: settings, remoteActive: remote.active)
    }

    func saveSettings(_ next: PublicSettings, apiKey: String? = nil, clearAPIKey: Bool = false) {
        try? settingsStore.save(next, apiKey: apiKey, clearAPIKey: clearAPIKey)
        listen.configure(settings: settingsStore.settings)
        hotkeys.register(settings.hotkeyMap)
        remote.updateHotkeys(settings.hotkeyMap)
        applyWindowChrome()
    }

    func newChat() {
        let conversation = Conversation()
        container.mainContext.insert(conversation)
        try? container.mainContext.save()
        reloadConversations()
        activeID = conversation.identifier
        draft = ""
        attachments = []
    }

    func deleteConversation(_ conversation: Conversation) {
        container.mainContext.delete(conversation)
        try? container.mainContext.save()
        if activeID == conversation.identifier {
            activeID = nil
        }
        reloadConversations()
        if activeID == nil {
            newChat()
        }
    }

    func send() {
        if isStreaming {
            cancelToken?.cancel()
            streamTask?.cancel()
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard let apiKey = KeychainAPIKeyStore.load() else {
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
        insert(assistant, into: conversation)
        isStreaming = true
        let continuation = ChatContinuationBuilder.build(from: conversation.messages.map { $0.asTurn() }.filter { $0.id != assistantID })
        let token = CancellationToken()
        cancelToken = token
        let snapshot = settings
        streamTask = Task {
            do {
                for try await event in client.stream(apiKey: apiKey, settings: snapshot, continuation: continuation, signal: token) {
                    apply(event, assistantID: assistantID, conversation: conversation)
                }
            } catch {
                apply(.error(error.localizedDescription), assistantID: assistantID, conversation: conversation)
            }
            isStreaming = false
        }
    }

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
        if let panel { remote.stop(panel: panel) }
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

    private func appendDraft(_ text: String) {
        if draft.isEmpty {
            draft = text
        } else {
            draft += " " + text
        }
    }

    private func applyRemoteText(_ text: String) {
        if text == "\u{8}" {
            if !draft.isEmpty { draft.removeLast() }
            return
        }
        draft += text
    }

    private func insert(_ turn: ChatTurn, into conversation: Conversation) {
        let message = Message(identifier: turn.id, role: turn.role, content: turn.content, createdAt: turn.createdAt, status: turn.status)
        message.apply(turn)
        message.conversation = conversation
        conversation.messages.append(message)
        conversation.updatedAt = .now
        try? container.mainContext.save()
        reloadConversations()
    }

    private func apply(_ event: ChatStreamEvent, assistantID: UUID, conversation: Conversation) {
        guard let message = conversation.messages.first(where: { $0.identifier == assistantID }) else { return }
        switch event {
        case .start:
            break
        case .delta(let delta):
            message.content += delta
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
        case .done(let timing, let responseID):
            message.statusRaw = MessageStatus.complete.rawValue
            message.timingJSON = try? JSONEncoder().encode(timing)
            message.responseID = responseID
        case .error(let text):
            message.statusRaw = MessageStatus.error.rawValue
            if message.content.isEmpty {
                message.content = text
            }
        }
        conversation.updatedAt = .now
        try? container.mainContext.save()
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
