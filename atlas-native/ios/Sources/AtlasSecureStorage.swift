import Foundation
import Security

protocol AtlasKeychainAccess {
    func read(_ query: [CFString: Any]) -> (OSStatus, Data?)
    func update(_ query: [CFString: Any], data: Data) -> OSStatus
    func insert(_ query: [CFString: Any]) -> OSStatus
    func delete(_ query: [CFString: Any]) -> OSStatus
}

struct AtlasSystemKeychain: AtlasKeychainAccess {
    func read(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func update(_ query: [CFString: Any], data: Data) -> OSStatus {
        SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    }

    func insert(_ query: [CFString: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

enum AtlasSecureStorage {
    static func load(_ key: String, keychain: any AtlasKeychainAccess = AtlasSystemKeychain()) throws -> String? {
        var query = attributes(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = keychain.read(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data,
              let value = String(data: data, encoding: .utf8) else { throw storageError() }
        return value
    }

    static func save(_ key: String, value: String, keychain: any AtlasKeychainAccess = AtlasSystemKeychain()) throws {
        let query = attributes(key)
        let data = Data(value.utf8)
        let status = keychain.update(query, data: data)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard keychain.insert(item) == errSecSuccess else { throw storageError() }
        } else if status != errSecSuccess { throw storageError() }
    }

    static func delete(_ key: String, keychain: any AtlasKeychainAccess = AtlasSystemKeychain()) throws {
        let status = keychain.delete(attributes(key))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError() }
    }

    private static func attributes(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "dev.tuist.atlas.oauth", kSecAttrAccount: key]
    }

    private static func storageError() -> AtlasAuthenticationError {
        AtlasAuthenticationError(kind: "storage", message: "Could not access the Atlas Keychain. Try again.")
    }
}
