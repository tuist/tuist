import Foundation
import Security
import Testing
import UserNotifications

struct AtlasPushTests {
    @Test func completionCategoryOffersOnlyAnUnlockedForegroundOpen() throws {
        let category = AtlasPushActions.orbitCompletedCategory
        #expect(category.identifier == "ATLAS_ORBIT_COMPLETED")
        #expect(category.actions.count == 1)
        let action = try #require(category.actions.first)
        #expect(action.identifier == "ATLAS_OPEN_CONVERSATION")
        #expect(action.title == "Open conversation")
        #expect(action.options == [.foreground, .authenticationRequired])
        #expect(!(action is UNTextInputNotificationAction))
    }

    @Test func onlyDefaultTapsAndTheMatchingOpenActionNavigate() {
        let link = "dev.tuist.atlas://navigate/orbit/0b6b9c2e-8f8e-4b1e-9a51-1f3d2b7f0c11?server=https%3A%2F%2Fatlas.tuist.dev"
        let payload: [AnyHashable: Any] = [
            "schema_version": 1, "url": link
        ]
        let category = AtlasPushActions.orbitCompletedCategoryID
        for action in [UNNotificationDefaultActionIdentifier, AtlasPushActions.openConversationID] {
            #expect(AtlasPushPayload.destination(payload, actionIdentifier: action, categoryIdentifier: category) != nil)
        }
        for action in [UNNotificationDismissActionIdentifier, "UNKNOWN_ACTION", "", "REPLY"] {
            #expect(AtlasPushPayload.destination(payload, actionIdentifier: action, categoryIdentifier: category) == nil)
        }
        #expect(AtlasPushPayload.destination(
            payload, actionIdentifier: AtlasPushActions.openConversationID, categoryIdentifier: ""
        ) == nil)
        #expect(AtlasPushPayload.destination(
            payload, actionIdentifier: UNNotificationDefaultActionIdentifier, categoryIdentifier: ""
        ) != nil)
        #expect(AtlasPushPayload.destination(
            ["schema_version": 2, "url": link],
            actionIdentifier: AtlasPushActions.openConversationID, categoryIdentifier: category
        ) == nil)
    }

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
        let notifications = AtlasPushNotifications(store: store, system: PushSystem().adapter)
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
        ], actionIdentifier: AtlasPushActions.openConversationID, categoryIdentifier: AtlasPushActions.orbitCompletedCategoryID))
        navigation.receive(wrongOrigin, server: server)
        #expect(navigation.message != nil)
        #expect(navigation.destination == nil)
    }
}

@MainActor
extension AtlasPushTests {
    @Test func environmentRequiresAnExactBuildStamp() {
        #expect(AtlasPushSystem.environment(from: "development") == "sandbox")
        #expect(AtlasPushSystem.environment(from: "production") == "production")
        for stamp in [nil, "", "sandbox", "debug", "Production", "$(ATLAS_PUSH_ENVIRONMENT)"] {
            #expect(AtlasPushSystem.environment(from: stamp) == nil)
        }
    }

    @Test func unsignedBuildNeverPromptsOrRegisters() async throws {
        let system = PushSystem()
        system.environment = nil
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let notifications = AtlasPushNotifications(store: store, system: system.adapter)
        await notifications.configure(server: server) { _ in Issue.record("No server write expected"); return Data() }
        await notifications.enable()
        await notifications.refresh(token: "stale-token")
        #expect(!notifications.enabled && notifications.message != nil)
        #expect(system.prompts == 0 && system.registrations == 0)
        #expect(try store.load(origin: server.absoluteString) == nil)
    }

    @Test func deniedPermissionNeverStoresOptIn() async throws {
        let system = PushSystem()
        system.granted = false
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let notifications = AtlasPushNotifications(store: store, system: system.adapter)
        await notifications.configure(server: server) { _ in Data() }
        await notifications.enable()
        #expect(!notifications.enabled && system.prompts == 1 && system.registrations == 0)
        #if os(macOS)
        #expect(notifications.message?.contains("System Settings") == true)
        #else
        #expect(notifications.message?.contains("iOS Settings") == true)
        #endif
        #expect(try store.load(origin: server.absoluteString) == nil)
    }

    @Test func registersPlatformAndTokenRotationThenMarksDisabledBeforeOfflineCleanup() async throws {
        let system = PushSystem()
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let notifications = AtlasPushNotifications(store: store, system: system.adapter)
        var tokens: [String] = []
        await notifications.configure(server: server) { action in
            if action["action"] as? String == "unregister" {
                #expect(try store.load(origin: server.absoluteString)?.enabled == false)
                throw CocoaError(.fileReadUnknown)
            }
            #if os(macOS)
            #expect(action["platform"] as? String == "macos")
            #else
            #expect(action["platform"] as? String == "ios")
            #endif
            #expect(action["environment"] as? String == "sandbox")
            #expect(try action["installation_id"] as? String == store.load(origin: server.absoluteString)?.installationID)
            tokens.append(try #require(action["token"] as? String))
            return Data()
        }
        await notifications.enable()
        #expect(notifications.enabled && system.registrations == 1)
        await notifications.refresh(token: "first-token")
        await notifications.refresh(token: "rotated-token")
        #expect(tokens == ["first-token", "rotated-token"])
        await notifications.signOut()
        #expect(!notifications.enabled && system.unregistrations == 1 && system.clears == 1)
        #expect(try store.load(origin: server.absoluteString)?.enabled == false)
        await notifications.refresh(token: "late-token")
        #expect(tokens.count == 2)
    }

    @Test func reenablingResyncsAnUnchangedAPNsTokenWithoutAnotherCallback() async throws {
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let notifications = AtlasPushNotifications(store: store, system: PushSystem().adapter)
        var registrations: [String] = []
        var installations: [String] = []
        await notifications.configure(server: server) { action in
            if action["action"] as? String == "register" {
                registrations.append(try #require(action["token"] as? String))
                installations.append(try #require(action["installation_id"] as? String))
            }
            return Data()
        }
        await notifications.enable()
        await notifications.refresh(token: "unchanged-token")
        await notifications.disable()
        await notifications.enable()
        #expect(notifications.enabled)
        #expect(registrations == ["unchanged-token", "unchanged-token"])
        #expect(installations.count == 2 && installations[0] != installations[1])
    }

    @Test func revokedPermissionUnregistersWithoutSendingTheStaleToken() async throws {
        let system = PushSystem()
        system.status = .denied
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        try store.save(AtlasPushRegistration(installationID: UUID().uuidString.lowercased(),
                                           origin: server.absoluteString, enabled: true))
        let notifications = AtlasPushNotifications(store: store, system: system.adapter)
        var actions: [String] = []
        await notifications.configure(server: server) { action in
            actions.append(try #require(action["action"] as? String))
            #expect(try store.load(origin: server.absoluteString)?.enabled == false)
            return Data()
        }
        await notifications.refresh(token: "stale-token")
        #expect(actions == ["unregister"] && !notifications.enabled)
        #expect(try store.load(origin: server.absoluteString) == nil)
    }

    @Test func rejectedStartupSessionDisablesOnlySavedOriginBeforeConfiguration() throws {
        let system = PushSystem()
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let first = "https://atlas.tuist.dev/"
        let second = "https://atlas.example.org/"
        for origin in [first, second] {
            try store.save(AtlasPushRegistration(installationID: UUID().uuidString.lowercased(), origin: origin, enabled: true))
        }
        let notifications = AtlasPushNotifications(store: store, system: system.adapter)
        notifications.prepareForSessionEnd(origin: first)
        #expect(try store.load(origin: first)?.enabled == false)
        #expect(try store.load(origin: second)?.enabled == true)
        #expect(system.unregistrations == 1 && system.clears == 1)
    }

    @Test func lateRegistrationConflictCannotRenewASignedOutSession() async throws {
        let system = PushSystem()
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let notifications = AtlasPushNotifications(store: store, system: system.adapter)
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Error>?
        var calls = 0
        await notifications.configure(server: server) { _ in
            calls += 1
            return try await withCheckedThrowingContinuation { finish = $0; started.continuation.yield(()) }
        }
        await notifications.enable()
        let refresh = Task { await notifications.refresh(token: "old-session-token") }
        for await _ in started.stream { break }
        notifications.prepareForSessionEnd()
        finish?.resume(throwing: AtlasAuthenticationError(kind: "conflict", message: "Deleted installation"))
        await refresh.value
        #expect(calls == 1 && !notifications.enabled && !notifications.busy && notifications.message == nil)
        #expect(try store.load(origin: server.absoluteString)?.enabled == false)
    }

    @Test func lateConsentCannotReenableAnEndedSession() async throws {
        let system = PushSystem()
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Bool, Never>?
        var adapter = system.adapter
        adapter.requestAuthorization = {
            await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
        }
        let notifications = AtlasPushNotifications(store: store, system: adapter)
        await notifications.configure(server: server) { _ in Data() }
        let enable = Task { await notifications.enable() }
        for await _ in started.stream { break }
        notifications.prepareForSessionEnd()
        finish?.resume(returning: true)
        await enable.value
        #expect(!notifications.enabled && !notifications.busy && system.registrations == 0)
        #expect(try store.load(origin: server.absoluteString) == nil)
    }

    @Test func deletedInstallationIsReplacedOnlyAfterSuccessfulCleanup() async throws {
        let store = AtlasPushRegistrationStore(keychain: PushKeychain())
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let original = UUID().uuidString.lowercased()
        try store.save(AtlasPushRegistration(installationID: original, origin: server.absoluteString, enabled: true))
        let notifications = AtlasPushNotifications(store: store, system: PushSystem().adapter)
        var actions: [String] = []
        await notifications.configure(server: server) { action in
            let name = try #require(action["action"] as? String)
            let id = try #require(action["installation_id"] as? String)
            actions.append(name)
            if actions.count == 1 {
                #expect(name == "register" && id == original)
                throw AtlasAuthenticationError(kind: "conflict", message: "Deleted installation")
            }
            if name == "unregister" {
                #expect(id == original)
                #expect(try store.load(origin: server.absoluteString)?.installationID == original)
            } else {
                #expect(id != original && UUID(uuidString: id) != nil)
                #expect(try store.load(origin: server.absoluteString)?.installationID == id)
            }
            return Data()
        }
        await notifications.refresh(token: "valid-token")
        #expect(actions == ["register", "unregister", "register"] && notifications.enabled)
        #expect(try store.load(origin: server.absoluteString)?.installationID != original)
    }

    @Test func coldStartNotificationIsPendingUntilOriginBoundSignIn() throws {
        let navigation = AtlasNavigation()
        let server = try #require(URL(string: "https://atlas.tuist.dev/"))
        let link = "dev.tuist.atlas://navigate/orbit/0b6b9c2e-8f8e-4b1e-9a51-1f3d2b7f0c11?server=https%3A%2F%2Fatlas.tuist.dev"
        let url = try #require(AtlasPushPayload.destination(["schema_version": 1, "url": link]))
        navigation.receive(url, server: nil)
        #expect(navigation.pending != nil && navigation.destination == nil)
        navigation.resolve(server: server)
        #expect(navigation.pending == nil && navigation.destination?.recordID == "0b6b9c2e-8f8e-4b1e-9a51-1f3d2b7f0c11")
        #expect(navigation.selection == "orbit")
    }
}

@MainActor
private final class PushSystem {
    var environment: String? = "sandbox"
    var granted = true
    var status: UNAuthorizationStatus = .authorized
    var prompts = 0
    var registrations = 0
    var unregistrations = 0
    var clears = 0

    var adapter: AtlasPushSystem {
        AtlasPushSystem(
            requestAuthorization: { self.prompts += 1; return self.granted },
            authorizationStatus: { self.status },
            register: { self.registrations += 1 }, unregister: { self.unregistrations += 1 },
            clearNotifications: { self.clears += 1 }, environment: { self.environment }
        )
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
