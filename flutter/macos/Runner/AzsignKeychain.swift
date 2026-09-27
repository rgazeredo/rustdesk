import Foundation
import Security

enum AzsignKeychain {
    static let service = "com.azsign.rustdesk.desktop"
    static let allowedKeys: Set<String> = ["azsign_desktop_device_id", "azsign_desktop_access_token"]

    static func query(_ key: String) throws -> [String: Any] {
        guard allowedKeys.contains(key) else { throw failure(errSecParam) }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    static func read(_ key: String) throws -> String? {
        var request = try query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw failure(status) }
        return value
    }

    static func write(_ key: String, value: String) throws {
        guard !value.isEmpty && value.utf8.count <= 4096 else { throw failure(errSecParam) }
        let request = try query(key)
        let data = Data(value.utf8)
        var status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = request
            insert[kSecValueData as String] = data
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }

    static func delete(_ key: String) throws {
        let status = SecItemDelete(try query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    static func failure(_ status: OSStatus) -> NSError {
        return NSError(domain: service, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Armazenamento seguro indisponível (\(status))."])
    }
}
