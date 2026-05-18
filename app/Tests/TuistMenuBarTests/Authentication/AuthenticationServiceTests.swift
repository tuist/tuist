import Foundation
import Path
import Testing
import TuistAppStorage
import TuistAuthentication
import TuistServer

@Suite struct AuthenticationServiceTests {
    private let serverURL = URL(string: "https://tuist.dev")!

    @Test func deleting_credentials_logs_the_user_out() async throws {
        let store = makeCredentialsStore()
        let appStorage = TestAppStorage(
            authenticationState: .loggedIn(account: Account(email: "tuist@tuist.dev", handle: "tuist"))
        )
        let subject = await makeAuthenticationService(
            store: store,
            appStorage: appStorage
        )

        try await store.delete(serverURL: serverURL)
        try await waitUntil {
            subject.authenticationState == .loggedOut
        }

        #expect(subject.authenticationState == .loggedOut)
        #expect(try appStorage.get(AuthenticationStateKey.self) == .loggedOut)
    }

    @Test func storing_credentials_without_account_claims_logs_the_user_out() async throws {
        let store = makeCredentialsStore()
        let appStorage = TestAppStorage(
            authenticationState: .loggedIn(account: Account(email: "tuist@tuist.dev", handle: "tuist"))
        )
        let subject = await makeAuthenticationService(
            store: store,
            appStorage: appStorage
        )

        try await store.store(
            credentials: makeCredentials(
                accessToken: try JWT.make(
                    expiryDate: Date().addingTimeInterval(600),
                    typ: "access"
                ).token,
                refreshToken: try JWT.make(
                    expiryDate: Date().addingTimeInterval(3600),
                    typ: "refresh"
                ).token
            ),
            serverURL: serverURL
        )

        try await waitUntil {
            subject.authenticationState == .loggedOut
        }

        #expect(subject.authenticationState == .loggedOut)
        #expect(try appStorage.get(AuthenticationStateKey.self) == .loggedOut)
    }

    @Test func separate_store_instances_with_shared_storage_leave_the_original_service_stale() async throws {
        let sharedConfigDirectory = makeTemporaryDirectory()
        let rootStore = makeCredentialsStore(configDirectory: sharedConfigDirectory)
        let loginStore = makeCredentialsStore(configDirectory: sharedConfigDirectory)
        let rootAppStorage = TestAppStorage(authenticationState: .loggedOut)
        let loginAppStorage = TestAppStorage(authenticationState: .loggedOut)
        let rootService = await makeAuthenticationService(
            store: rootStore,
            appStorage: rootAppStorage
        )
        let loginService = await makeAuthenticationService(
            store: loginStore,
            appStorage: loginAppStorage
        )
        let account = Account(email: "tuist@tuist.dev", handle: "tuist")
        let credentials = try makeCredentials(
            email: account.email,
            handle: account.handle
        )

        try await loginStore.store(
            credentials: credentials,
            serverURL: serverURL
        )

        try await waitUntil {
            loginService.authenticationState == .loggedIn(account: account)
        }

        let storedCredentials = try #require(
            try await rootStore.read(serverURL: serverURL)
        )

        for _ in 0 ..< 20 {
            await Task.yield()
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(storedCredentials == credentials)
        #expect(loginService.authenticationState == .loggedIn(account: account))
        #expect(rootService.authenticationState == .loggedOut)
    }

    private func makeAuthenticationService(
        store: ServerCredentialsStore,
        appStorage: TestAppStorage
    ) async -> AuthenticationService {
        await ServerCredentialsStore.$current.withValue(store) {
            AuthenticationService(appStorage: appStorage)
        }
    }

    private func makeCredentialsStore(
        configDirectory: AbsolutePath? = nil
    ) -> ServerCredentialsStore {
        ServerCredentialsStore(
            backend: .fileSystem,
            configDirectory: configDirectory ?? makeTemporaryDirectory()
        )
    }

    private func makeTemporaryDirectory() -> AbsolutePath {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return try! AbsolutePath(validating: path.path)
    }

    private func makeCredentials(
        email: String = "tuist@tuist.dev",
        handle: String = "tuist"
    ) throws -> ServerCredentials {
        try makeCredentials(
            accessToken: JWT.make(
                expiryDate: Date().addingTimeInterval(600),
                typ: "access",
                email: email,
                preferredUsername: handle
            ).token,
            refreshToken: JWT.make(
                expiryDate: Date().addingTimeInterval(3600),
                typ: "refresh",
                email: email,
                preferredUsername: handle
            ).token
        )
    }

    private func makeCredentials(
        accessToken: String,
        refreshToken: String
    ) throws -> ServerCredentials {
        ServerCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }

    private func waitUntil(
        _ predicate: () -> Bool
    ) async throws {
        for _ in 0 ..< 100 {
            if predicate() {
                return
            }
            await Task.yield()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class TestAppStorage: AppStoring, @unchecked Sendable {
    private var authenticationState: AuthenticationState

    init(authenticationState: AuthenticationState) {
        self.authenticationState = authenticationState
    }

    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        if key.key == AuthenticationStateKey.key {
            return authenticationState as! Key.Value
        }
        return key.defaultValue
    }

    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        if key.key == AuthenticationStateKey.key,
           let value = value as? AuthenticationState
        {
            authenticationState = value
        }
    }
}
