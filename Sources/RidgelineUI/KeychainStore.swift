#if canImport(Security)
import Foundation
import Security

/// Small wrapper for secrets such as the routing server token. Secrets never go in the data file.
/// Not yet compiled or run: needs Xcode.
enum KeychainStore {
    private static let service = "app.ridgelineops"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        SecItemDelete(query(key) as CFDictionary)
        guard !value.isEmpty else { return true }
        var item = query(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func load(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#endif
