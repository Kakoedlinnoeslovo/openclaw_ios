import Foundation
import Security

enum Keychain {

    static func save(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveString(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        save(data, service: AppConstants.keychainService, account: key)
    }

    static func loadString(forKey key: String) -> String? {
        guard let data = load(service: AppConstants.keychainService, account: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteValue(forKey key: String) {
        delete(service: AppConstants.keychainService, account: key)
    }
}
