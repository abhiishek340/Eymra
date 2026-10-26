import Foundation
import Security
import os

/// Generic-password storage for the AI Judge API key.
nonisolated enum Keychain {
    private static let service = "app.eymra.judge"
    /// UI tests run unsigned on the Simulator, where the Keychain refuses writes; they keep keys in memory instead.
    private static let memory = OSAllocatedUnfairLock<[String: String]?>(initialState: nil)

    static func useMemoryStore() { memory.withLock { $0 = [:] } }

    static func read(_ account: String) -> String? {
        if let store = memory.withLock({ $0 }) { return store[account] }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        if memory.withLock({ $0 != nil }) {
            memory.withLock { $0?[account] = value.isEmpty ? nil : value }
            return true
        }
        delete(account)
        guard !value.isEmpty else { return true }
        let attrs: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                                      kSecValueData: Data(value.utf8),
                                      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }
}
