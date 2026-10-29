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

    @MainActor @Test func accountSettingsReusesSessionModelWithoutCallingASignedOutBridge() async {
        let authentication = AtlasAuthentication()
        let accounts = authentication.accountSettings
        #expect(accounts === authentication.accountSettings)
        await accounts.load()
        #expect(accounts.errorMessage == "Sign in to Atlas again.")
        #expect(authentication.server == nil && !authentication.busy)
    }

    @Test func googleLoginKeepsTheNativeCallbackAndPKCE() async throws {
        let request: [String: Any] = [
            "operation": "begin",
            "server": "https://atlas.example",
            "provider": AtlasLoginProvider.google.rawValue,
            "registration": [
                "server": "https://atlas.example/",
                "authorization_endpoint": "https://atlas.example/oauth2/authorize",
                "token_endpoint": "https://atlas.example/oauth2/token",
                "client_id": "test-native-client"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        let input = try #require(String(data: data, encoding: .utf8))
        let result = try await AtlasAuthBridge.execute(input)
        let response = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let login = try #require(response["ok"] as? [String: Any])
        let address = try #require(login["authorization_url"] as? String)
        let url = try #require(URLComponents(string: address))
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value) })
        let pending = try #require(login["pending"] as? [String: Any])
        #expect(url.host == "atlas.example" && url.path == "/oauth2/authorize")
        #expect(query["provider"] == "google")
        #expect(query["redirect_uri"] == "dev.tuist.atlas://oauth-callback")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == pending["state"] as? String)
        #expect((pending["verifier"] as? String)?.count == 43)
    }

    @Test func rustBridgeRejectsUnsafeServerWithoutNetwork() async throws {
        let result = try await AtlasAuthBridge.execute("{\"operation\":\"begin\",\"server\":\"http://atlas.example\"}")
        let response = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let failure = try #require(response["error"] as? [String: String])
        #expect(failure["kind"] == "invalid_server")
        #expect(response["ok"] == nil)
    }

    #if os(macOS)
    @MainActor @Test func failedEnvironmentEnrollmentNeverRestoresConsentAndLoadCanRetry() async throws {
        let keychain = FakeKeychain()
        let origin = try #require(URL(string: "https://atlas.example.org/"))
        let owner = UUID().uuidString.lowercased()
        let request: AtlasWorkstation.Request = { action in
            guard action["action"] as? String == "list" else { throw CocoaError(.fileReadUnknown) }
            return Data("{\"owner_id\":\"\(owner)\",\"environments\":[]}".utf8)
        }
        let live: AtlasWorkstation.Request = { _ in Issue.record("Disabled consent must not connect"); throw CancellationError() }
        let model = AtlasWorkstation(origin: origin, request: request, live: live, keychain: keychain)
        keychain.failure = errSecInteractionNotAllowed
        await model.load()
        #expect(!model.available && !model.configuration.enabled)
        keychain.failure = nil
        await model.load()
        #expect(model.available && !model.configuration.enabled)
        var draft = model.configuration
        draft.enabled = true
        draft.folders = [AtlasWorkstationFolder(path: FileManager.default.temporaryDirectory.path)]
        await model.save(draft)
        #expect(!model.configuration.enabled && model.message != nil)
        let restored = AtlasWorkstation(origin: origin, request: request, live: live, keychain: keychain)
        await restored.load()
        #expect(restored.available && !restored.configuration.enabled)
        #expect(restored.configuration.id == draft.id)
        let otherOwner = UUID().uuidString.lowercased()
        let other = AtlasWorkstation(origin: origin, request: { _ in
            Data("{\"owner_id\":\"\(otherOwner)\",\"environments\":[]}".utf8)
        }, live: live, keychain: keychain)
        await other.load()
        #expect(other.configuration.id != draft.id && !other.configuration.enabled && other.configuration.folders.isEmpty)
    }
    #endif
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
