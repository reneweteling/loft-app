import Foundation
import Security

enum KeychainStore {
    private static let service = "com.weteling.loft"
    private static let accessKeyAccount = "aws.accessKeyId"
    private static let secretAccount = "aws.secretAccessKey"

    static func setAccessKey(_ value: String) { set(value, account: accessKeyAccount) }
    static func setSecretKey(_ value: String) { set(value, account: secretAccount) }
    static func accessKey() -> String? { get(account: accessKeyAccount) }
    static func secretKey() -> String? { get(account: secretAccount) }

    static func hasCredentials() -> Bool {
        guard let a = accessKey(), !a.isEmpty,
              let s = secretKey(), !s.isEmpty else { return false }
        return true
    }

    static func clear() {
        delete(account: accessKeyAccount)
        delete(account: secretAccount)
    }

    private static func set(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess,
              let data = out as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
