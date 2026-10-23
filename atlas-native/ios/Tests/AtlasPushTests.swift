import Foundation
import Security
import Testing

struct AtlasPushTests {
    @Test func acceptsOnlyVersionedCustomSchemeNavigationHints() throws {
        let link = "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.tuist.dev"
        #expect(AtlasPushPayload.destination(["schema_version": 1, "url": link])?.absoluteString == link)
        #expect(AtlasPushPayload.destination(["schema_version": "1", "url": link]) != nil)
        for value in ["https://evil.example", "dev.tuist.atlas://oauth-callback?code=secret", "file:///private/data"] {
            #expect(AtlasPushPayload.destination(["schema_version": 1, "url": value]) == nil)
        }
        #expect(AtlasPushPayload.destination(["schema_version": 2, "url": link]) == nil)
        #expect(AtlasPushPayload.destination(["url": link]) == nil)
        #expect(AtlasPushPayload.destination(["schema_version": 1, "url": String(repeating: "x", count: 2049)]) == nil)
    }

    @Test func encryptedRegistrationStoreKeepsCleanupSeparateForEachOrigin() throws {
        let keychain = PushKeychain()
        let store = AtlasPushRegistrationStore(keychain: keychain)
        let first = "https://atlas.tuist.dev/"
        let second = "https://atlas.example.org/"
        try store.save(AtlasPushRegistration(installationID: UUID().uuidString.lowercased(), origin: first, enabled: false))
        try store.save(AtlasPushRegistration(installationID: UUID().uuidString.lowercased(), origin: second, enabled: true))
        #expect(try store.load(origin: first)?.enabled == false)
        #expect(try store.load(origin: second)?.enabled == true)
        try store.delete(origin: second)
        #expect(try store.load(origin: first) != nil)
        #expect(try store.load(origin: second) == nil)
    }

    @Test func failedPushBookkeepingFallsBackToDeletingOnlyItsOwnRecord() throws {
        let keychain = PushKeychain()
        let store = AtlasPushRegistrationStore(keychain: keychain)
        let origin = "https://atlas.tuist.dev/"
        try store.save(AtlasPushRegistration(installationID: UUID().uuidString.lowercased(), origin: origin, enabled: true))
        keychain.rejectUpdates = true
        store.disableForSessionEnd(origin: origin)
        #expect(try store.load(origin: origin) == nil)
        keychain.rejectUpdates = false
        try AtlasSecureStorage.save("push-registration:" + origin, value: "corrupt-json", keychain: keychain)
        store.disableForSessionEnd(origin: origin)
        #expect(try store.load(origin: origin) == nil)
    }

    @MainActor @Test func cleanupIsRetriedOnlyOnItsOwnServerAndSurvivesFailure() async throws {
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let first = "https://atlas.tuist.dev/"
        let second = try #require(URL(string: "https://atlas.example.org/"))
        let id = UUID().uuidString.lowercased()
        try store.save(AtlasPushRegistration(installationID: id, origin: first, enabled: false))
        let notifications = AtlasPushNotifications(store: store)
        var calls = 0
        await notifications.configure(server: second) { _ in calls += 1; return Data() }
        #expect(calls == 0)
        #expect(!notifications.enabled)
        await notifications.configure(server: URL(string: first)) { action in
            calls += 1
            #expect(action["action"] as? String == "unregister")
            #expect(action["installation_id"] as? String == id)
            throw CocoaError(.fileReadUnknown)
        }
        #expect(calls == 1)
        #expect(try store.load(origin: first)?.enabled == false)
        #expect(notifications.message != nil)
        await notifications.configure(server: URL(string: first)) { _ in Data("{\"deleted\":true}".utf8) }
        #expect(try store.load(origin: first) == nil)
        #expect(!notifications.enabled)
    }

    @MainActor @Test func notificationHintsStillUseOriginAndScreenValidation() throws {
        let navigation = AtlasNavigation()
        let server = try #require(URL(string: "https://atlas.tuist.dev"))
        let wrongOrigin = try #require(AtlasPushPayload.destination([
            "schema_version": 1, "url": "dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fevil.example"
        ]))
        navigation.receive(wrongOrigin, server: server)
        #expect(navigation.message != nil)
    }
}

private final class PushKeychain: AtlasKeychainAccess {
    private var values: [String: Data] = [:]
    var rejectUpdates = false

    func read(_ query: [CFString: Any]) -> (OSStatus, Data?) {
        guard let data = values[account(query)] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func update(_ query: [CFString: Any], data: Data) -> OSStatus {
        if rejectUpdates { return errSecInteractionNotAllowed }
        guard values[account(query)] != nil else { return errSecItemNotFound }
        values[account(query)] = data
        return errSecSuccess
    }

    func insert(_ query: [CFString: Any]) -> OSStatus {
        values[account(query)] = query[kSecValueData] as? Data
        return errSecSuccess
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        values.removeValue(forKey: account(query))
        return errSecSuccess
    }

    private func account(_ query: [CFString: Any]) -> String { query[kSecAttrAccount] as? String ?? "" }
}
