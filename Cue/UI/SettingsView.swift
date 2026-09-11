import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var session: AppSession
    @State private var section = 0
    @State private var apiKey = ""
    @State private var draft = PublicSettings.default

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                List(selection: $section) {
                    Text("AI provider").tag(0)
                    Text("Interview listen").tag(1)
                    Text("Hotkeys").tag(2)
                    Text("Data controls").tag(3)
                }
                .frame(width: 190)
                Group {
                    switch section {
                    case 0: provider
                    case 1: listen
                    case 2: hotkeys
                    default: data
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { session.settingsOpen = false }
                Button("Save") {
                    try? session.settingsStore.save(
                        draft,
                        apiKey: apiKey.isEmpty ? nil : apiKey,
                        clearAPIKey: false
                    )
                    session.saveSettings(session.settingsStore.settings)
                    session.settingsOpen = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 720, height: 520)
        .cueGlass(cornerRadius: 20)
        .onAppear { draft = session.settings }
    }

    private var provider: some View {
        Form {
            LabeledContent("API key") {
                VStack(alignment: .leading) {
                    SecureField("sk-…", text: $apiKey)
                    if let hint = session.settings.keyHint {
                        Text("Saved: \(hint)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Picker("Model", selection: $draft.model) {
                ForEach(ModelCatalog.models) { model in
                    Text(model.label).tag(model.id)
                }
            }
            Picker("Thinking", selection: $draft.reasoningEffort) {
                ForEach(ModelCatalog.definition(for: draft.model).supportedEfforts, id: \.self) { effort in
                    Text(ModelCatalog.definition(for: effort).label).tag(effort)
                }
            }
            Toggle("Web search", isOn: $draft.webSearchEnabled)
            TextField("System instruction", text: $draft.systemInstruction, axis: .vertical)
                .lineLimit(4...8)
        }
    }

    private var listen: some View {
        Form {
            Picker("Listen mode", selection: $draft.listenMode) {
                ForEach(ListenMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(draft.listenMode.help).font(.caption).foregroundStyle(.secondary)
            Picker("Whisper model", selection: $draft.whisperModel) {
                ForEach(WhisperModelID.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            Toggle("Audio auto mode (VAD)", isOn: $draft.audioAutoMode)
            if draft.listenMode == .accessibility {
                Text(AccessibilityTrust.isTrusted ? "Accessibility is granted." : "Cue needs Accessibility plus Live Captions.")
                    .font(.caption)
                Button("Request Accessibility") { AccessibilityTrust.request() }
            }
        }
    }

    private var hotkeys: some View {
        Form {
            Toggle("Passive focus mode", isOn: $draft.passiveFocusMode)
            Toggle("Always on top", isOn: $draft.alwaysOnTop)
            Slider(value: $draft.windowOpacity, in: 0.15...1) {
                Text("Opacity")
            }
            ForEach(HotkeyCatalog.items) { item in
                LabeledContent(item.label) {
                    TextField("", text: binding(for: item.id))
                        .frame(width: 220)
                }
            }
        }
    }

    private var data: some View {
        Form {
            Toggle("Stealth mode (hide from screen capture)", isOn: $draft.stealthMode)
            Button("Export current chat") {
                exportActive()
            }
            Button("Delete all chats", role: .destructive) {
                for conversation in session.conversations {
                    session.deleteConversation(conversation)
                }
            }
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
