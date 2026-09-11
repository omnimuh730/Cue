import Foundation
import Security

nonisolated enum APIKeyStore {
    private static let service = "com.sidgroup.Cue"
    private static let account = "openai-api-key"
    private static let hintDefaultsKey = "cue.api-key-hint"

    static func load() -> String? {
        if let key = readFile() { return key }
        return readKeychain()
    }

    static func hint() -> String? {
        if let stored = UserDefaults.standard.string(forKey: hintDefaultsKey), !stored.isEmpty {
            return stored
        }
        return Self.hint(for: load())
    }

    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try writeFile(trimmed)
        try writeKeychain(trimmed)
        UserDefaults.standard.set(hint(for: trimmed), forKey: hintDefaultsKey)
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: hintDefaultsKey)
        deleteFile()
        deleteKeychain()
    }

    static func hint(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        if key.count >= 8 {
            return "\(key.prefix(3))…\(key.suffix(4))"
        }
        return String(repeating: "•", count: max(4, key.count))
    }

    private static func fileURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Cue", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appending(path: "openai-api-key", directoryHint: .notDirectory)
    }

    private static func readFile() -> String? {
        guard let url = try? fileURL(),
              let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    private static func writeFile(_ key: String) throws {
        let url = try fileURL()
        try Data(key.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func deleteFile() {
        guard let url = try? fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    private static func writeKeychain(_ key: String) throws {
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw ChatError.transport("Could not save the API key to Keychain (\(status)).")
        }
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
