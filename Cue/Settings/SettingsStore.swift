import Foundation

nonisolated enum ListenMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case whisper
    case appleSpeech
    case accessibility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whisper: "Whisper"
        case .appleSpeech: "Apple Speech"
        case .accessibility: "Accessibility"
        }
    }

    var help: String {
        switch self {
        case .whisper: "System speaker audio transcribed on-device with WhisperKit."
        case .appleSpeech: "System speaker audio transcribed with Apple SpeechAnalyzer."
        case .accessibility: "Reads Apple Live Captions through Accessibility. No audio capture in Cue."
        }
    }
}

nonisolated enum WhisperModelID: String, Codable, CaseIterable, Sendable, Identifiable {
    case baseEn = "base.en"
    case smallEn = "small.en"
    case mediumEn = "medium.en"

    var id: String { rawValue }

    var whisperKitName: String { rawValue }

    var label: String {
        switch self {
        case .baseEn: "Base English"
        case .smallEn: "Small English"
        case .mediumEn: "Medium English"
        }
    }
}

struct PublicSettings: Codable, Equatable, Sendable {
    var model: ModelID
    var reasoningEffort: ReasoningEffort
    var stealthMode: Bool
    var webSearchEnabled: Bool
    var whisperModel: WhisperModelID
    var listenMode: ListenMode
    var audioAutoMode: Bool
    var alwaysOnTop: Bool
    var windowOpacity: Double
    var passiveFocusMode: Bool
    var systemInstruction: String
    var hotkeys: [String: String]
    /// Optional path to a `codex` CLI for project chats. Nil means auto-detect.
    var codexPath: String?
    /// Stored optional so settings saved before this field existed still decode; read
    /// `readingOrder` instead.
    private var storedReadingOrder: ReadingOrder?

    var readingOrder: ReadingOrder {
        get { storedReadingOrder ?? .newestAtBottom }
        set { storedReadingOrder = newValue }
    }

    static let `default` = PublicSettings(
        model: .sol,
        reasoningEffort: .low,
        stealthMode: true,
        webSearchEnabled: false,
        whisperModel: .smallEn,
        listenMode: .whisper,
        audioAutoMode: true,
        alwaysOnTop: false,
        windowOpacity: 1,
        passiveFocusMode: true,
        systemInstruction: "",
        hotkeys: Dictionary(uniqueKeysWithValues: HotkeyCatalog.defaults.map { ($0.key.rawValue, $0.value) }),
        codexPath: nil,
        storedReadingOrder: nil
    )

    var hotkeyMap: HotkeyMap {
        var map: HotkeyMap = [:]
        for (key, value) in hotkeys {
            if let action = HotkeyAction(rawValue: key) {
                map[action] = value
            }
        }
        return HotkeyCatalog.normalize(map)
    }

    mutating func setHotkeys(_ map: HotkeyMap) {
        hotkeys = Dictionary(uniqueKeysWithValues: HotkeyCatalog.normalize(map).map { ($0.key.rawValue, $0.value) })
    }

    var hasAPIKey: Bool { APIKeyStore.load() != nil }

    var keyHint: String? { APIKeyStore.hint() }
}

@MainActor
@Observable
final class SettingsStore {
    private let defaultsKey = "cue.public-settings"
    private(set) var settings: PublicSettings

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(PublicSettings.self, from: data) {
            var next = decoded
            next.reasoningEffort = ModelCatalog.normalizeEffort(next.reasoningEffort, for: next.model)
            next.setHotkeys(next.hotkeyMap)
            settings = next
        } else {
            settings = .default
        }
    }

    func save(_ update: PublicSettings, apiKey: String? = nil, clearAPIKey: Bool = false) throws {
        var next = update
        next.reasoningEffort = ModelCatalog.normalizeEffort(next.reasoningEffort, for: next.model)
        next.systemInstruction = SystemInstruction.normalize(next.systemInstruction)
        next.windowOpacity = min(1, max(0.15, next.windowOpacity))
        next.setHotkeys(next.hotkeyMap)
        if let path = next.codexPath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            next.codexPath = path.isEmpty ? nil : path
        }
        if clearAPIKey {
            APIKeyStore.delete()
        } else if let apiKey {
            try APIKeyStore.save(apiKey)
        }
        settings = next
        persist()
    }

    func patch(_ body: (inout PublicSettings) -> Void) {
        var next = settings
        body(&next)
        try? save(next)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
