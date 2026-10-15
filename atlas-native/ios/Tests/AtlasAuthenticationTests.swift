import Foundation
import Security
import Testing

struct AtlasAuthenticationTests {
    @Test func secureStorageRoundTripUpdateAndDelete() throws {
        let keychain = FakeKeychain()
        #expect(try AtlasSecureStorage.load("session", keychain: keychain) == nil)
        try AtlasSecureStorage.save("session", value: "first-credential", keychain: keychain)
        #expect(try AtlasSecureStorage.load("session", keychain: keychain) == "first-credential")
        #expect(keychain.lastInsert?[kSecAttrAccessible] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(keychain.lastInsert?[kSecClass] as? String == kSecClassGenericPassword as String)
        #expect(keychain.lastInsert?[kSecAttrService] as? String == "dev.tuist.atlas.oauth")
        try AtlasSecureStorage.save("session", value: "rotated-credential", keychain: keychain)
        #expect(try AtlasSecureStorage.load("session", keychain: keychain) == "rotated-credential")
        try AtlasSecureStorage.delete("session", keychain: keychain)
        #expect(try AtlasSecureStorage.load("session", keychain: keychain) == nil)
        try AtlasSecureStorage.delete("session", keychain: keychain)
    }

    @Test func secureStorageDoesNotTreatFailuresAsMissingCredentials() {
        let keychain = FakeKeychain()
        keychain.failure = errSecInteractionNotAllowed
        #expect(throws: AtlasAuthenticationError.self) { try AtlasSecureStorage.load("session", keychain: keychain) }
        #expect(throws: AtlasAuthenticationError.self) { try AtlasSecureStorage.save("session", value: "secret", keychain: keychain) }
        #expect(throws: AtlasAuthenticationError.self) { try AtlasSecureStorage.delete("session", keychain: keychain) }
        #expect(keychain.lastInsert == nil)
    }

    @Test func rustBridgeRejectsUnsafeServerWithoutNetwork() async throws {
        let result = try await AtlasAuthBridge.execute("{\"operation\":\"begin\",\"server\":\"http://atlas.example\"}")
        let response = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let failure = try #require(response["error"] as? [String: String])
        #expect(failure["kind"] == "invalid_server")
        #expect(response["ok"] == nil)
    }
}

private final class FakeKeychain: AtlasKeychainAccess {
    var values: [String: Data] = [:]
    var lastInsert: [CFString: Any]?
    var failure: OSStatus?

    func read(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        if let failure { return (failure, nil) }
        let value = values[query[kSecAttrAccount] as? String ?? ""]
        return (value == nil ? errSecItemNotFound : errSecSuccess, value)
    }

    func update(_ query: [CFString: Any], data: Data) -> OSStatus {
        if let failure { return failure }
        guard let key = query[kSecAttrAccount] as? String, values[key] != nil else { return errSecItemNotFound }
        values[key] = data
        return errSecSuccess
    }

    func insert(_ query: [CFString: Any]) -> OSStatus {
        if let failure { return failure }
        lastInsert = query
        guard let key = query[kSecAttrAccount] as? String, let data = query[kSecValueData] as? Data else { return errSecParam }
        values[key] = data
        return errSecSuccess
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        if let failure { return failure }
        guard let key = query[kSecAttrAccount] as? String else { return errSecParam }
        return values.removeValue(forKey: key) == nil ? errSecItemNotFound : errSecSuccess
    }
}
