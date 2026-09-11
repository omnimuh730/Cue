import AppKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case provider
    case listen
    case hotkeys
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: "AI provider"
        case .listen: "Interview listen"
        case .hotkeys: "Hotkeys"
        case .data: "Data controls"
        }
    }

    var symbol: String {
        switch self {
        case .provider: "key.fill"
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
            apiKey = ""
            clearKey = false
            replacingKey = false
            saveError = nil
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
            ForEach(HotkeyCatalog.items) { item in
                CueGlassField(title: item.label, help: item.description) {
                    TextField("Shortcut", text: binding(for: item.id))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
        }
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
        }
    }

    private func binding(for action: HotkeyAction) -> Binding<String> {
        Binding(
            get: { draft.hotkeyMap[action] ?? "" },
            set: { value in
                var map = draft.hotkeyMap
                map[action] = value
                draft.setHotkeys(map)
            }
        )
    }

    private func exportActive() {
        let text = session.activeTurns.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
