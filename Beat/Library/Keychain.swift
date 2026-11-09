import Foundation
import Security

/// A few secrets (the Discogs token) in the login keychain rather than in plain preferences.
enum Keychain {
    private static var service: String { Bundle.main.bundleIdentifier ?? "Beat" }

    static func string(for account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `value`, or deletes the item when it's nil or empty.
    static func set(_ value: String?, for account: String) {
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        guard let value, !value.isEmpty else {
            SecItemDelete(match as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        if SecItemUpdate(match as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var add = match
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
