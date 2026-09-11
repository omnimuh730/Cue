import Foundation
import Security

enum KeychainAPIKeyStore {
    private static let service = "com.sidgroup.Cue"
    private static let account = "openai-api-key"

    static func load() -> String? {
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

    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        delete()
        guard !trimmed.isEmpty else { return }
        guard let data = trimmed.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ChatError.transport("Could not save the API key (\(status)).")
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hint(for key: String?) -> String? {
        guard let key, key.count >= 8 else { return key.map { String(repeating: "•", count: max(4, $0.count)) } }
        return "\(key.prefix(3))…\(key.suffix(4))"
    }
}
