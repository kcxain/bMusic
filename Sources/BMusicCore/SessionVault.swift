import Foundation
import Security

struct SessionVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.github.kcxain.BMusic", kSecAttrAccount as String: "bilibili-session"]
    }
    func read() throws -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw error(status) }
        return value as? Data
    }
    func write(_ data: Data) throws {
        let values = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(q as CFDictionary, nil)
            guard result == errSecSuccess else { throw error(result) }; return
        }
        guard status == errSecSuccess else { throw error(status) }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }
    private func error(_ status: OSStatus) -> BMusicError {
        .storage((SecCopyErrorMessageString(status, nil) as String?) ?? "钥匙串错误 \(status)")
    }
}
