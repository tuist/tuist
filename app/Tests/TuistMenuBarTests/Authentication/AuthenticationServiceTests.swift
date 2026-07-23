import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAppStorage
import TuistAuthentication
import TuistServer

@Suite struct AuthenticationServiceTests {
    private let serverURL = URL(string: "https://tuist.dev")!

    @Test(.inTemporaryDirectory) func deleting_credentials_logs_the_user_out() async throws {
        let store = try makeCredentialsStore()
        let account = Account(email: "tuist@tuist.dev", handle: "tuist")
        try await store.store(
            credentials: makeCredentials(email: account.email, handle: account.handle),
            serverURL: serverURL
        )
        let appStorage = TestAppStorage(
            authenticationState: .loggedIn(
                account: account,
                serverURL: serverURL
            )
        )
        let subject = await makeAuthenticationService(
            store: store,
            appStorage: appStorage
        )
        await subject.refreshAuthenticationStateForActiveServer()
        #expect(await subject.authenticationState == .loggedIn(account: account, serverURL: serverURL))

        try await store.delete(serverURL: serverURL)
        try await waitUntil {
            await subject.authenticationState == .loggedOut
        }

        #expect(await subject.authenticationState == .loggedOut)
        #expect(try appStorage.get(AuthenticationStateKey.self) == .loggedOut)
    }

    @Test(.inTemporaryDirectory) func storing_credentials_without_account_claims_logs_the_user_out() async throws {
        let store = try makeCredentialsStore()
        let account = Account(email: "tuist@tuist.dev", handle: "tuist")
        try await store.store(
            credentials: makeCredentials(email: account.email, handle: account.handle),
            serverURL: serverURL
        )
        let appStorage = TestAppStorage(
            authenticationState: .loggedIn(
                account: account,
                serverURL: serverURL
            )
        )
        let subject = await makeAuthenticationService(
            store: store,
            appStorage: appStorage
        )
        await subject.refreshAuthenticationStateForActiveServer()
        #expect(await subject.authenticationState == .loggedIn(account: account, serverURL: serverURL))

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
            await subject.authenticationState == .loggedOut
        }

        #expect(await subject.authenticationState == .loggedOut)
        #expect(try appStorage.get(AuthenticationStateKey.self) == .loggedOut)
    }

    @Test(.inTemporaryDirectory) func separate_store_instances_with_shared_storage_leave_the_original_service_stale()
        async throws
    {
        let sharedConfigDirectory = try makeTemporaryDirectory()
        let rootStore = try makeCredentialsStore(configDirectory: sharedConfigDirectory)
        let loginStore = try makeCredentialsStore(configDirectory: sharedConfigDirectory)
        let rootAppStorage = TestAppStorage(authenticationState: .loggedOut)
        let loginAppStorage = TestAppStorage(authenticationState: .loggedOut)
        let account = Account(email: "tuist@tuist.dev", handle: "tuist")
        let credentials = try makeCredentials(
            email: account.email,
            handle: account.handle
        )
        try await rootStore.store(
            credentials: credentials,
            serverURL: serverURL
        )
        let rootService = await makeAuthenticationService(
            store: rootStore,
            appStorage: rootAppStorage
        )
        try await waitUntil {
            await rootService.authenticationState == .loggedIn(account: account, serverURL: serverURL)
        }
        try await rootStore.delete(serverURL: serverURL)
        try await waitUntil {
            await rootService.authenticationState == .loggedOut
        }

        let loginService = await makeAuthenticationService(
            store: loginStore,
            appStorage: loginAppStorage
        )

        try await loginStore.store(
            credentials: credentials,
            serverURL: serverURL
        )

        try await waitUntil {
            await loginService.authenticationState == .loggedIn(account: account, serverURL: serverURL)
        }

        let storedCredentials = try #require(
            try await rootStore.read(serverURL: serverURL)
        )

        for _ in 0 ..< 20 {
            await Task.yield()
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(storedCredentials == credentials)
        #expect(await loginService.authenticationState == .loggedIn(account: account, serverURL: serverURL))
        #expect(await rootService.authenticationState == .loggedOut)
    }

    @Test(.inTemporaryDirectory) func updating_the_server_url_restores_credentials_bound_to_that_url() async throws {
        let customServerURL = URL(string: "https://custom.tuist.dev")!
        let store = try makeCredentialsStore()
        let appStorage = TestAppStorage(authenticationState: .loggedOut)
        let account = Account(email: "custom@tuist.dev", handle: "custom")
        let credentials = try makeCredentials(
            email: account.email,
            handle: account.handle
        )
        try await store.store(credentials: credentials, serverURL: customServerURL)
        let subject = await makeAuthenticationService(
            store: store,
            appStorage: appStorage
        )

        try await subject.updateServerURL(customServerURL.absoluteString)
        try await waitUntil {
            await subject.authenticationState == .loggedIn(account: account, serverURL: customServerURL)
        }

        #expect(await subject.serverURL == customServerURL)
        #expect(await subject.authenticationState == .loggedIn(account: account, serverURL: customServerURL))
        #expect(try appStorage.get(AppServerURLKey.self) == customServerURL.absoluteString)
    }

    @Test(.inTemporaryDirectory) func stored_authentication_state_for_another_server_starts_logged_out() async throws {
        let customServerURL = URL(string: "https://custom.tuist.dev")!
        let account = Account(email: "custom@tuist.dev", handle: "custom")
        let appStorage = TestAppStorage(
            authenticationState: .loggedIn(account: account, serverURL: customServerURL)
        )
        let store = try makeCredentialsStore()

        let subject = await makeAuthenticationService(
            store: store,
            appStorage: appStorage
        )

        #expect(await subject.authenticationState == .loggedOut)
    }

    @Test(.inTemporaryDirectory) func resetting_the_server_url_restores_default_server_credentials() async throws {
        let customServerURL = URL(string: "https://custom.tuist.dev")!
        let defaultAccount = Account(email: "default@tuist.dev", handle: "default")
        let customAccount = Account(email: "custom@tuist.dev", handle: "custom")
        let store = try makeCredentialsStore()
        try await store.store(
            credentials: makeCredentials(email: defaultAccount.email, handle: defaultAccount.handle),
            serverURL: serverURL
        )
        try await store.store(
            credentials: makeCredentials(email: customAccount.email, handle: customAccount.handle),
            serverURL: customServerURL
        )
        let appStorage = TestAppStorage(
            authenticationState: .loggedOut,
            serverURLString: customServerURL.absoluteString
        )
        let subject = await makeAuthenticationService(store: store, appStorage: appStorage)
        await subject.refreshAuthenticationStateForActiveServer()

        try await subject.resetServerURL()
        try await waitUntil {
            await subject.authenticationState == .loggedIn(account: defaultAccount, serverURL: serverURL)
        }

        #expect(await subject.serverURL == serverURL)
        #expect(await subject.authenticationState == .loggedIn(account: defaultAccount, serverURL: serverURL))
        #expect(try appStorage.get(AppServerURLKey.self) == nil)
    }

    @Test(.inTemporaryDirectory) func signing_out_removes_only_the_active_server_credentials() async throws {
        let customServerURL = URL(string: "https://custom.tuist.dev")!
        let defaultCredentials = try makeCredentials(email: "default@tuist.dev", handle: "default")
        let customCredentials = try makeCredentials(email: "custom@tuist.dev", handle: "custom")
        let store = try makeCredentialsStore()
        try await store.store(credentials: defaultCredentials, serverURL: serverURL)
        try await store.store(credentials: customCredentials, serverURL: customServerURL)
        let appStorage = TestAppStorage(
            authenticationState: .loggedOut,
            serverURLString: customServerURL.absoluteString
        )
        let subject = await makeAuthenticationService(store: store, appStorage: appStorage)
        await subject.refreshAuthenticationStateForActiveServer()

        await subject.signOut()

        #expect(try await store.read(serverURL: customServerURL) == nil)
        #expect(try await store.read(serverURL: serverURL) == defaultCredentials)
        #expect(await subject.authenticationState == .loggedOut)
    }

    @Test(.timeLimit(.minutes(1))) func stale_refresh_does_not_restore_credentials_after_sign_out() async throws {
        let account = Account(email: "tuist@tuist.dev", handle: "tuist")
        let store = SuspendingReadCredentialsStore(
            credentials: try makeCredentials(email: account.email, handle: account.handle),
            notifiesWhenDeleting: false
        )
        let appStorage = TestAppStorage(authenticationState: .loggedOut)
        let subject = await makeAuthenticationService(store: store, appStorage: appStorage)
        try await waitUntil {
            await subject.authenticationState == .loggedIn(account: account, serverURL: serverURL)
        }

        await store.suspendNextRead()
        let refreshTask = Task {
            await subject.refreshAuthenticationStateForActiveServer()
        }
        try await waitUntil {
            await store.readIsSuspended()
        }

        await subject.signOut()
        await store.resumeSuspendedRead()
        await refreshTask.value

        #expect(await subject.authenticationState == .loggedOut)
        #expect(try appStorage.get(AuthenticationStateKey.self) == .loggedOut)
    }

    @Test(.timeLimit(.minutes(1))) func credential_change_invalidates_a_suspended_refresh() async throws {
        let account = Account(email: "tuist@tuist.dev", handle: "tuist")
        let store = SuspendingReadCredentialsStore(
            credentials: try makeCredentials(email: account.email, handle: account.handle),
            notifiesWhenDeleting: true
        )
        let appStorage = TestAppStorage(authenticationState: .loggedOut)
        let subject = await makeAuthenticationService(store: store, appStorage: appStorage)
        try await waitUntil {
            await subject.authenticationState == .loggedIn(account: account, serverURL: serverURL)
        }

        await store.suspendNextRead()
        let refreshTask = Task {
            await subject.refreshAuthenticationStateForActiveServer()
        }
        try await waitUntil {
            await store.readIsSuspended()
        }

        await store.delete(serverURL: serverURL)
        try await waitUntil {
            await subject.authenticationState == .loggedOut
        }
        await store.resumeSuspendedRead()
        await refreshTask.value

        #expect(await subject.authenticationState == .loggedOut)
        #expect(try appStorage.get(AuthenticationStateKey.self) == .loggedOut)
    }

    @Test(.inTemporaryDirectory, .timeLimit(.minutes(1)))
    func deleting_an_account_does_not_sign_out_a_newly_selected_server() async throws {
        let customServerURL = URL(string: "https://custom.tuist.dev")!
        let defaultAccount = Account(email: "default@tuist.dev", handle: "default")
        let customAccount = Account(email: "custom@tuist.dev", handle: "custom")
        let defaultCredentials = try makeCredentials(email: defaultAccount.email, handle: defaultAccount.handle)
        let customCredentials = try makeCredentials(email: customAccount.email, handle: customAccount.handle)
        let store = try makeCredentialsStore()
        try await store.store(credentials: defaultCredentials, serverURL: serverURL)
        try await store.store(credentials: customCredentials, serverURL: customServerURL)
        let deleteAccountService = SuspendingDeleteAccountService()
        let appStorage = TestAppStorage(authenticationState: .loggedOut)
        let subject = await makeAuthenticationService(
            store: store,
            appStorage: appStorage,
            deleteAccountService: deleteAccountService
        )
        await subject.refreshAuthenticationStateForActiveServer()

        let deletionTask = Task {
            try await subject.deleteAccount(defaultAccount)
        }
        try await waitUntil {
            await deleteAccountService.deletionHasStarted()
        }
        try await subject.updateServerURL(customServerURL.absoluteString)
        try await waitUntil {
            await subject.authenticationState == .loggedIn(account: customAccount, serverURL: customServerURL)
        }
        await deleteAccountService.completeDeletion()
        try await deletionTask.value

        #expect(await deleteAccountService.requestedServerURL() == serverURL)
        #expect(try await store.read(serverURL: serverURL) == nil)
        #expect(try await store.read(serverURL: customServerURL) == customCredentials)
        #expect(await subject.authenticationState == .loggedIn(account: customAccount, serverURL: customServerURL))
    }

    @Test func normalized_server_url_adds_https_scheme() throws {
        let url = try AppServerEnvironmentService.normalizedURL(from: "custom.tuist.dev")

        #expect(url.absoluteString == "https://custom.tuist.dev")
    }

    @Test func normalized_server_url_rejects_unsupported_schemes() throws {
        #expect(throws: AppServerEnvironmentServiceError.unsupportedServerURLScheme("ftp")) {
            try AppServerEnvironmentService.normalizedURL(from: "ftp://custom.tuist.dev")
        }
    }

    @Test func normalized_server_url_allows_clear_text_localhost() throws {
        let url = try AppServerEnvironmentService.normalizedURL(from: "http://localhost:8080/")

        #expect(url.absoluteString == "http://localhost:8080")
    }

    @Test func normalized_server_url_allows_clear_text_internet_protocol_version_six_loopback() throws {
        let url = try AppServerEnvironmentService.normalizedURL(from: "http://[::1]:8080")

        #expect(url.absoluteString == "http://[::1]:8080")
    }

    @Test func normalized_server_url_canonicalizes_the_host_and_default_port() throws {
        let url = try AppServerEnvironmentService.normalizedURL(from: "HTTPS://CUSTOM.TUIST.DEV:443/")

        #expect(url.absoluteString == "https://custom.tuist.dev")
    }

    @Test func normalized_server_url_rejects_clear_text_remote_hosts() {
        #expect(throws: AppServerEnvironmentServiceError.insecureServerURL) {
            try AppServerEnvironmentService.normalizedURL(from: "http://custom.tuist.dev")
        }
        #expect(throws: AppServerEnvironmentServiceError.insecureServerURL) {
            try AppServerEnvironmentService.normalizedURL(from: "http://127.example.com")
        }
    }

    @Test func normalized_server_url_rejects_non_root_paths() {
        #expect(throws: AppServerEnvironmentServiceError.serverURLMustBeRoot) {
            try AppServerEnvironmentService.normalizedURL(from: "https://custom.tuist.dev/api")
        }
    }

    private func makeAuthenticationService(
        store: ServerCredentialsStoring,
        appStorage: TestAppStorage,
        deleteAccountService: DeleteAccountServicing = DeleteAccountService()
    ) async -> AuthenticationService {
        return await AuthenticationService(
            serverEnvironmentService: AppServerEnvironmentService(
                appStorage: appStorage,
                defaultServerEnvironmentService: TestServerEnvironmentService(serverURL: serverURL)
            ),
            appStorage: appStorage,
            credentialsStore: store,
            deleteAccountService: deleteAccountService
        )
    }

    private func makeCredentialsStore(
        configDirectory: AbsolutePath? = nil
    ) throws -> ServerCredentialsStore {
        return ServerCredentialsStore(
            backend: .fileSystem,
            configDirectory: try configDirectory ?? makeTemporaryDirectory()
        )
    }

    private func makeTemporaryDirectory() throws -> AbsolutePath {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        return temporaryDirectory.appending(component: UUID().uuidString)
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
        _ predicate: () async -> Bool
    ) async throws {
        for _ in 0 ..< 100 {
            if await predicate() {
                return
            }
            await Task.yield()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw AuthenticationServiceTestError.timedOut
    }
}

private enum AuthenticationServiceTestError: Error {
    case timedOut
}

private actor SuspendingReadCredentialsStore: ServerCredentialsStoring {
    nonisolated let credentialsChanged: AsyncStream<ServerCredentials?>

    private let credentialsChangedContinuation: AsyncStream<ServerCredentials?>.Continuation
    private let notifiesWhenDeleting: Bool
    private var credentials: ServerCredentials?
    private var shouldSuspendNextRead = false
    private var isReadSuspended = false
    private var suspendedReadContinuation: CheckedContinuation<Void, Never>?

    init(
        credentials: ServerCredentials?,
        notifiesWhenDeleting: Bool
    ) {
        let stream = AsyncStream<ServerCredentials?>.makeStream()
        credentialsChanged = stream.stream
        credentialsChangedContinuation = stream.continuation
        self.credentials = credentials
        self.notifiesWhenDeleting = notifiesWhenDeleting
    }

    func store(credentials: ServerCredentials, serverURL _: URL) {
        self.credentials = credentials
        credentialsChangedContinuation.yield(credentials)
    }

    func get(serverURL _: URL) throws -> ServerCredentials {
        guard let credentials else {
            throw SuspendingReadCredentialsStoreError.credentialsNotFound
        }
        return credentials
    }

    func read(serverURL _: URL) async -> ServerCredentials? {
        let credentials = credentials
        guard shouldSuspendNextRead else {
            return credentials
        }

        shouldSuspendNextRead = false
        isReadSuspended = true
        await withCheckedContinuation { continuation in
            suspendedReadContinuation = continuation
        }
        return credentials
    }

    func delete(serverURL _: URL) {
        credentials = nil
        if notifiesWhenDeleting {
            credentialsChangedContinuation.yield(nil)
        }
    }

    func suspendNextRead() {
        shouldSuspendNextRead = true
    }

    func readIsSuspended() -> Bool {
        return isReadSuspended
    }

    func resumeSuspendedRead() {
        isReadSuspended = false
        suspendedReadContinuation?.resume()
        suspendedReadContinuation = nil
    }
}

private enum SuspendingReadCredentialsStoreError: Error {
    case credentialsNotFound
}

private actor SuspendingDeleteAccountService: DeleteAccountServicing {
    private var deletionContinuation: CheckedContinuation<Void, Never>?
    private var deletionStarted = false
    private var serverURL: URL?

    func deleteAccount(handle _: String, serverURL: URL) async throws {
        self.serverURL = serverURL
        deletionStarted = true
        await withCheckedContinuation { continuation in
            deletionContinuation = continuation
        }
    }

    func deletionHasStarted() -> Bool {
        return deletionStarted
    }

    func completeDeletion() {
        deletionContinuation?.resume()
        deletionContinuation = nil
    }

    func requestedServerURL() -> URL? {
        return serverURL
    }
}

private final class TestAppStorage: AppStoring, @unchecked Sendable {
    private var authenticationState: AuthenticationState
    private var serverURLString: String?

    init(
        authenticationState: AuthenticationState,
        serverURLString: String? = nil
    ) {
        self.authenticationState = authenticationState
        self.serverURLString = serverURLString
    }

    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        if key.key == AuthenticationStateKey.key {
            return authenticationState as! Key.Value
        }
        if key.key == AppServerURLKey.key {
            return (serverURLString as String?) as! Key.Value
        }
        return key.defaultValue
    }

    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        if key.key == AuthenticationStateKey.key,
           let value = value as? AuthenticationState
        {
            authenticationState = value
        }
        if key.key == AppServerURLKey.key {
            serverURLString = value as? String
        }
    }
}

private struct TestServerEnvironmentService: ServerEnvironmentServicing {
    let serverURL: URL

    func url() -> URL {
        serverURL
    }

    func oauthClientId() -> String {
        "test-client-id"
    }

    func url(configServerURL _: URL) throws -> URL {
        serverURL
    }
}
