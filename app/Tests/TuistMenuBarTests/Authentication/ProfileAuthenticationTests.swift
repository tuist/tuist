import FileSystem
import FileSystemTesting
import Foundation
import OpenAPIRuntime
import os
import TestCoverageAttribution
import Testing
import TuistAppStorage
import TuistHTTP
import TuistServer
@testable import TuistAuthentication

@Suite(.coverageAttribution)
@MainActor
struct ProfileAuthenticationTests {
    private let personal = Account(email: "personal@example.com", handle: "personal")
    private let employer = Account(email: "employee@example.com", handle: "employee")
    private var serverURL: URL { ServerEnvironmentService().url() }

    @Test(.inTemporaryDirectory, arguments: [
        nil,
        AppServerConfiguration(url: URL(string: "https://company.example.com")!, oauthClientID: "fixture-client"),
    ])
    func upgrade_rotation_and_restart_keep_the_legacy_profile(server: AppServerConfiguration?) async throws {
        let url = server?.url ?? serverURL
        try await withProfiles(server: server) { service, storage, store, vault in
            let legacy = try await store.get(serverURL: url)
            try await service.loadProfiles()
            let originalID = try #require(service.activeProfileID)
            try await service.loadProfiles()
            #expect(service.profiles.count == 1)
            #expect(service.activeProfileID == originalID)
            #expect(try await store.get(serverURL: url) == legacy)
            #expect(service.authenticationState == .loggedIn(account: personal, server: server))

            let rotated = try credentials(personal, expiresIn: 7200)
            try await store.store(credentials: rotated, serverURL: url)
            try await service.loadProfiles()
            #expect(vault.value.profiles.first?.credentials == rotated)
            let restarted = AuthenticationService(appStorage: storage, profilesEnabled: true)
            restarted.profileStore = vault
            try await restarted.loadProfiles()
            #expect(restarted.activeProfileID == originalID)
            #expect(restarted.authenticationState == .loggedIn(account: personal, server: server))
            #expect(try await store.get(serverURL: url) == rotated)
        }
    }

    @Test(.inTemporaryDirectory) func adding_switching_and_signing_out_isolate_same_server_profiles() async throws {
        try await withProfiles { service, _, store, vault in
            try await service.loadProfiles()
            let personalID = try #require(service.activeProfileID)
            let original = try await store.get(serverURL: serverURL)
            let cache = CachedValueStore()
            let oldClient = ServerAuthenticationController(cachedValueStore: cache)
            #expect(try await oldClient.authenticationToken(serverURL: serverURL)?.value == original.accessToken)
            try await service.beginAddingProfile()
            try await service.selectServer(nil)
            try await service.signInWithEmailAndPassword(email: employer.email, password: "fixture")
            let employerID = try #require(service.activeProfileID)
            #expect(personalID != employerID)
            #expect(service.profiles.count == 2)
            #expect(service.authenticationState == .loggedIn(account: employer))
            #expect(vault.value.profiles.first(where: { $0.id == personalID })?.credentials == original)
            await #expect(throws: CancellationError.self) {
                try await oldClient.authenticationToken(serverURL: serverURL)
            }
            await #expect(throws: CancellationError.self) {
                try await oldClient.refreshToken(serverURL: serverURL)
            }
            let newClient = ServerAuthenticationController(cachedValueStore: cache)
            #expect(try await newClient.authenticationToken(serverURL: serverURL)?.value == credentials(employer).accessToken)
            try await service.switchProfile(personalID)
            #expect(service.authenticationState == .loggedIn(account: personal))
            #expect(try await store.get(serverURL: serverURL) == original)
            await service.signOut()
            #expect(service.profiles.map(\.id) == [employerID])
            #expect(service.authenticationState == .loggedIn(account: employer))
        }
    }

    @Test(.inTemporaryDirectory) func profile_switching_does_not_require_organization_discovery() async throws {
        let fixture = OrganizationFixture(names: [:])
        try await withProfiles(organizations: fixture) { service, _, store, vault in
            try await service.loadProfiles()
            let inactive = StoredProfile(id: UUID(), account: employer, server: nil, credentials: try credentials(employer))
            vault.value.profiles.append(inactive)
            await fixture.reject(employer.handle, error: ListOrganizationsServiceError.forbidden("Forbidden"))
            await service.refreshOrganizations()
            #expect(service.organizationsFailedToLoad)
            #expect(!service.organizations.contains { $0.profileID == inactive.id })

            try await service.switchProfile(inactive.id)

            #expect(service.authenticationState == .loggedIn(account: employer))
            #expect(service.activeProfileID == inactive.id)
            #expect(try await store.get(serverURL: serverURL) == inactive.credentials)
        }
    }

    @Test(.inTemporaryDirectory) func cancellation_and_failed_add_leave_existing_credentials_untouched() async throws {
        try await withProfiles { service, storage, store, vault in
            try await service.loadProfiles()
            let original = try await store.get(serverURL: serverURL)
            let originalID = service.activeProfileID
            let selection = AppServerConfiguration(url: URL(string: "https://company.example.com")!, oauthClientID: "company")
            try storage.set(AppServerConfigurationKey.self, value: selection)
            try await service.beginAddingProfile()
            try await service.selectServer(nil)
            service.cancelAddingProfile()
            #expect(try storage.get(AppServerConfigurationKey.self) == selection)
            #expect(service.activeProfileID == originalID)
            #expect(try await store.get(serverURL: serverURL) == original)

            try await service.beginAddingProfile()
            vault.failWrites = true
            await #expect(throws: ProfileStorageError.self) {
                try await service.signInWithEmailAndPassword(email: employer.email, password: "fixture")
            }
            #expect(service.activeProfileID == originalID)
            #expect(service.authenticationState == .loggedIn(account: personal))
            #expect(try await store.get(serverURL: serverURL) == original)
            vault.failWrites = false
            service.cancelAddingProfile()
        }
    }

    @Test(.inTemporaryDirectory) func failed_switch_keeps_active_profile_and_all_saved_credentials() async throws {
        try await withProfiles { service, _, store, vault in
            try await service.loadProfiles()
            let personalID = try #require(service.activeProfileID)
            try await service.beginAddingProfile()
            try await service.signInWithEmailAndPassword(email: employer.email, password: "fixture")
            let employerID = service.activeProfileID
            let before = try await store.get(serverURL: serverURL)
            vault.failWrites = true
            await #expect(throws: ProfileStorageError.self) { try await service.switchProfile(personalID) }
            #expect(service.activeProfileID == employerID)
            #expect(service.authenticationState == .loggedIn(account: employer))
            #expect(try await store.get(serverURL: serverURL) == before)
            #expect(vault.value.profiles.count == 2)
        }
    }

    @Test(.inTemporaryDirectory) func failed_switch_restores_outgoing_notification_intent() async throws {
        try await withProfiles { service, _, _, vault in
            try await service.loadProfiles()
            let personalID = try #require(service.activeProfileID)
            try await service.beginAddingProfile()
            try await service.signInWithEmailAndPassword(email: employer.email, password: UUID().uuidString)
            var enabled = true
            service.beforeProfileChange = {
                enabled = false
                vault.failWrites = true
                return { enabled = true }
            }
            await #expect(throws: ProfileStorageError.self) { try await service.switchProfile(personalID) }
            #expect(enabled)
            #expect(service.authenticationState == .loggedIn(account: employer))
        }
    }

    @Test(.inTemporaryDirectory) func failed_inactive_rotation_is_retried_before_activation_without_reusing_old_tokens(
    ) async throws {
        let rotated = try credentials(employer, expiresIn: 8000)
        let fixture = OrganizationFixture(names: ["employee": ["team"]], rotations: ["employee": rotated])
        try await withProfiles(organizations: fixture) { service, _, store, vault in
            try await service.loadProfiles()
            let inactive = StoredProfile(id: UUID(), account: employer, server: nil, credentials: try credentials(employer))
            vault.value.profiles.append(inactive)
            await fixture.beforeRotation { vault.failWrites = true }
            await service.refreshOrganizations()
            #expect(service.organizationsFailedToLoad)
            #expect(vault.value.profiles.first { $0.id == inactive.id }?.credentials == inactive.credentials)
            await #expect(throws: ProfileStorageError.self) { try await service.switchProfile(inactive.id) }
            #expect(service.authenticationState == .loggedIn(account: personal))
            vault.failWrites = false
            try await service.switchProfile(inactive.id)
            #expect(try await store.get(serverURL: serverURL) == rotated)
            #expect(vault.value.profiles.first { $0.id == inactive.id }?.credentials == rotated)
        }
    }

    @Test(.inTemporaryDirectory) func switching_waits_for_rotation_and_archives_the_final_outgoing_tokens() async throws {
        try await withProfiles { service, _, store, vault in
            try await service.loadProfiles()
            let personalID = try #require(service.activeProfileID)
            let paused = PausedProfileRefresh()
            let controller = ServerAuthenticationController(
                refreshOAuthTokenService: paused, cachedValueStore: CachedValueStore()
            )
            let refreshing = Task { try await controller.refreshToken(serverURL: serverURL) }
            await paused.waitForRequest()
            let adding = Task {
                try await service.beginAddingProfile()
                try await service.signInWithEmailAndPassword(email: employer.email, password: UUID().uuidString)
            }
            for _ in 0 ..< 100 {
                if service.isChangingProfile { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(service.isChangingProfile)
            #expect(service.authenticationState == .loggedIn(account: personal))
            let rotated = try credentials(personal, expiresIn: 8000)
            await paused.respond(ServerAuthenticationTokens(
                accessToken: rotated.accessToken,
                refreshToken: rotated.refreshToken!
            ))
            _ = await refreshing.result
            try await adding.value
            #expect(service.authenticationState == .loggedIn(account: employer))
            #expect(vault.value.profiles.first(where: { $0.id == personalID })?.credentials == rotated)
            #expect(try await store.get(serverURL: serverURL).accessToken == credentials(employer).accessToken)
        }
    }

    @Test(.inTemporaryDirectory) func failed_sign_out_restores_credentials_and_saved_profile() async throws {
        try await withProfiles { service, storage, store, vault in
            try await service.loadProfiles()
            let originalID = service.activeProfileID
            let original = try await store.get(serverURL: serverURL)
            var notificationsEnabled = true
            service.beforeProfileChange = {
                notificationsEnabled = false
                return { notificationsEnabled = true }
            }
            storage.failSigningOut = true
            await service.signOut()
            #expect(notificationsEnabled)
            #expect(service.authenticationState == .loggedIn(account: personal))
            #expect(service.activeProfileID == originalID)
            #expect(vault.value.activeID == originalID)
            #expect(try await store.get(serverURL: serverURL) == original)
            storage.failSigningOut = false
            await service.signOut()
            #expect(!notificationsEnabled)
            #expect(service.authenticationState == .loggedOut)
            #expect(service.profiles.isEmpty)
            #expect(try await store.read(serverURL: serverURL) == nil)
        }
    }

    @Test(.inTemporaryDirectory) func organizations_are_flattened_and_switch_the_owning_login_and_global_scope() async throws {
        let fixture = OrganizationFixture(names: [
            "personal": ["shared", "personal-team"], "employee": ["shared", "employer-team"],
        ])
        try await withProfiles(organizations: fixture) { service, storage, store, vault in
            try await service.loadProfiles()
            let personalID = try #require(service.activeProfileID)
            try await service.beginAddingProfile()
            try await service.signInWithEmailAndPassword(email: employer.email, password: UUID().uuidString)
            await service.refreshOrganizations()
            #expect(service.organizations.contains { $0.name == "employer-team" })
            #expect(service.selectedOrganization == "employer-team")
            try await service.switchProfile(personalID)
            await service.refreshOrganizations()
            #expect(!service.organizationsFailedToLoad)
            #expect(service.organizations.map(\.name) == ["employer-team", "personal-team", "shared"])
            #expect(service.organizations.first { $0.name == "shared" }?.profileID == personalID)
            #expect(service.authenticationState == .loggedIn(account: personal))
            let scope = ServerAuthenticationSession.current.id
            let selected = try #require(service.organizations.first { $0.name == "employer-team" })
            try await service.switchOrganization(selected)
            #expect(service.authenticationState == .loggedIn(account: employer))
            #expect(service.selectedOrganization == "employer-team")
            #expect(service.activeProfileID == selected.profileID)
            #expect(ServerAuthenticationSession.current.id != scope)
            let activeCredentials = try await store.get(serverURL: serverURL)
            let expectedCredentials = try credentials(employer)
            #expect(activeCredentials.accessToken == expectedCredentials.accessToken)
            #expect(activeCredentials.refreshToken == expectedCredentials.refreshToken)
            #expect(activeCredentials.oauthClientID == nil)

            let restarted = AuthenticationService(appStorage: storage, profilesEnabled: true)
            restarted.profileStore = vault
            try await restarted.loadProfiles()
            #expect(restarted.selectedOrganization == "employer-team")
            let shared = try #require(restarted.organizations.first { $0.name == "shared" })
            let previousSession = ServerAuthenticationSession.current.id
            try await restarted.switchOrganization(shared)
            #expect(restarted.authenticationState == .loggedIn(account: employer))
            #expect(restarted.selectedOrganization == "shared")
            #expect(ServerAuthenticationSession.current.id != previousSession)
        }
    }

    @Test(.inTemporaryDirectory) func discovery_preserves_inactive_rotations_and_keeps_origins_distinct() async throws {
        let rotated = try credentials(employer, expiresIn: 8000)
        let fixture = OrganizationFixture(names: ["personal": ["team"], "employee": ["team"]], rotations: ["employee": rotated])
        try await withProfiles(organizations: fixture) { service, _, store, vault in
            try await service.loadProfiles()
            let original = try await store.get(serverURL: serverURL)
            let otherServer = AppServerConfiguration(url: URL(string: "https://company.example.com")!, oauthClientID: "other")
            let inactive = StoredProfile(
                id: UUID(),
                account: employer,
                server: otherServer,
                credentials: try credentials(employer)
            )
            vault.value.profiles.append(inactive)
            await service.refreshOrganizations()
            #expect(!service.organizationsFailedToLoad)
            #expect(service.organizations.count == 2)
            #expect(Set(service.organizations.map(\.id)).count == 2)
            #expect(service.authenticationState == .loggedIn(account: personal))
            #expect(try await store.get(serverURL: serverURL) == original)
            #expect(vault.value.profiles.first { $0.id == inactive.id }?.credentials == rotated)
            let selected = try #require(service.organizations.first { $0.profileID == inactive.id })
            try await service.switchOrganization(selected)
            #expect(service.authenticationState == .loggedIn(account: employer, server: otherServer))
            #expect(service.selectedOrganization == "team")
            #expect(try await store.get(serverURL: otherServer.url) == rotated)
        }
    }

    @Test(.inTemporaryDirectory) func offline_discovery_keeps_cached_memberships_and_the_existing_login() async throws {
        let fixture = OrganizationFixture(names: ["personal": ["team"]])
        try await withProfiles(organizations: fixture) { service, _, store, vault in
            await service.refreshOrganizations()
            let original = try await store.get(serverURL: serverURL)
            let previous = vault.value
            await fixture.fail()
            await service.refreshOrganizations()
            #expect(service.organizationsFailedToLoad)
            #expect(service.organizations.map(\.name) == ["team"])
            #expect(service.selectedOrganization == "team")
            #expect(vault.value == previous)
            #expect(try await store.get(serverURL: serverURL) == original)
            await fixture.replaceMemberships([:])
            await service.refreshOrganizations()
            #expect(!service.organizationsFailedToLoad)
            #expect(service.selectedOrganization == personal.handle)
            #expect(service.organizations.map(\.name) == [personal.handle])
            #expect(service.authenticationState == .loggedIn(account: personal))
            #expect(try await store.get(serverURL: serverURL) == original)
        }
    }

    @Test(.inTemporaryDirectory, arguments: [401, 403, 0, 1])
    func rejected_owner_does_not_hide_valid_login_and_recovers_after_success(status: Int) async throws {
        let colleague = Account(email: "colleague@example.com", handle: "colleague")
        let fixture = OrganizationFixture(names: ["employee": ["shared", "employee-team"], "colleague": ["shared"]])
        try await withProfiles(organizations: fixture) { service, storage, store, vault in
            try await service.loadProfiles()
            let original = try await store.get(serverURL: serverURL)
            let rejected = StoredProfile(id: UUID(), account: employer, server: nil, credentials: try credentials(employer))
            let eligible = StoredProfile(id: UUID(), account: colleague, server: nil, credentials: try credentials(colleague))
            vault.value.profiles.append(contentsOf: [rejected, eligible])
            await service.refreshOrganizations()
            let stale = try #require(service.organizations.first { $0.name == "shared" })
            #expect(stale.profileID == rejected.id)
            let failure: any Error = switch status {
            case 401: ListOrganizationsServiceError.unauthorized("Revoked")
            case 403: ListOrganizationsServiceError.forbidden("Removed")
            case 0: RefreshAuthTokenServiceError.unauthorized("Revoked refresh token")
            default: ClientError(
                    operationID: "listOrganizations", operationInput: "", causeDescription: "Credential acquisition failed",
                    underlyingError: CredentialAcquisitionError(
                        underlyingError: RefreshAuthTokenServiceError.unauthorized("Revoked refresh token")
                    )
                )
            }
            await fixture.reject(employer.handle, error: failure)
            await service.refreshOrganizations()
            #expect(service.organizationsFailedToLoad)
            #expect(service.authenticationState == .loggedIn(account: personal))
            #expect(try await store.get(serverURL: serverURL) == original)
            #expect(!service.organizations.contains { $0.profileID == rejected.id })
            #expect(service.organizations.first { $0.name == "shared" }?.profileID == eligible.id)
            await #expect(throws: ProfileStorageError.self) { try await service.switchOrganization(stale) }

            // Persisted rejection remains excluded even when the next launch is offline.
            let restarted = AuthenticationService(appStorage: storage, profilesEnabled: true, listOrganizationsService: fixture)
            restarted.profileStore = vault
            await fixture.fail()
            await restarted.refreshOrganizations()
            #expect(!restarted.organizations.contains { $0.profileID == rejected.id })
            #expect(restarted.organizations.first { $0.name == "shared" }?.profileID == eligible.id)

            let validChoice = try #require(service.organizations.first { $0.name == "shared" })
            try await service.switchOrganization(validChoice)
            #expect(service.authenticationState == .loggedIn(account: colleague))
            #expect(service.selectedOrganization == "shared")
            #expect(try await store.get(serverURL: serverURL) == eligible.credentials)

            await fixture.replaceMemberships(["employee": ["shared", "employee-team"], "colleague": ["shared"]])
            await service.refreshOrganizations()
            #expect(service.organizations.contains { $0.name == "employee-team" && $0.profileID == rejected.id })
        }
    }
}

extension ProfileAuthenticationTests {
    fileprivate func credentials(_ account: Account, expiresIn: TimeInterval = 3600) throws -> ServerCredentials {
        ServerCredentials(
            accessToken: try JWT.make(
                expiryDate: Date(timeIntervalSince1970: 4_000_000_000 + expiresIn),
                email: account.email, preferredUsername: account.handle, type: "account"
            ).token,
            refreshToken: try JWT.make(
                expiryDate: Date(timeIntervalSince1970: 4_100_000_000),
                email: account.email, preferredUsername: account.handle, type: "account"
            ).token,
            oauthClientID: "fixture-client"
        )
    }

    private func withProfiles(
        server: AppServerConfiguration? = nil,
        organizations: ListOrganizationsServicing = OrganizationFixture(names: [:]),
        _ action: (AuthenticationService, ProfileAppStorage, ServerCredentialsStore, MemoryProfileStore) async throws -> Void
    ) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let store = ServerCredentialsStore(backend: .fileSystem, configDirectory: directory)
        let storage = ProfileAppStorage()
        try storage.set(AuthenticationStateKey.self, value: .loggedIn(account: personal, server: server))
        let personalTokens = try credentials(personal)
        let employerTokens = try credentials(employer)
        try await store.store(credentials: personalTokens, serverURL: server?.url ?? serverURL)
        try await ServerAuthenticationSession.$current.withValue(ServerAuthenticationSession()) {
            try await ServerCredentialsStore.$current.withValue(store) {
                let service = AuthenticationService(
                    appStorage: storage,
                    profilesEnabled: true,
                    listOrganizationsService: organizations,
                    perform: { request in
                        let data = try JSONSerialization.data(withJSONObject: [
                            "access_token": employerTokens.accessToken, "refresh_token": employerTokens.refreshToken!,
                        ])
                        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                    }
                )
                let vault = MemoryProfileStore()
                service.profileStore = vault
                try await action(service, storage, store, vault)
            }
        }
    }
}

private actor OrganizationFixture: ListOrganizationsServicing {
    private var names: [String: [String]]
    let rotations: [String: ServerCredentials]
    private var failing = false
    private var errors: [String: any Error] = [:]
    private var onRotation: (@MainActor @Sendable () -> Void)?

    init(names: [String: [String]], rotations: [String: ServerCredentials] = [:]) {
        self.names = names
        self.rotations = rotations
    }

    func fail() { failing = true }

    func reject(_ handle: String, error: any Error) { errors[handle] = error }

    func beforeRotation(_ action: @escaping @MainActor @Sendable () -> Void) { onRotation = action }

    func replaceMemberships(_ names: [String: [String]]) {
        self.names = names
        failing = false
        errors = [:]
    }

    func listOrganizations(serverURL: URL) async throws -> [String] {
        if failing { throw URLError(.notConnectedToInternet) }
        let credentials = try await ServerCredentialsStore.current.get(serverURL: serverURL)
        let handle = try #require(JWT.parse(credentials.accessToken).preferredUsername)
        if let error = errors[handle] { throw error }
        if let rotated = rotations[handle] {
            await onRotation?()
            try await ServerCredentialsStore.current.store(credentials: rotated, serverURL: serverURL)
        }
        return names[handle] ?? []
    }
}

private final class MemoryProfileStore: ProfileStoring, Sendable {
    private struct State {
        var value = StoredProfiles()
        var failWrites = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    var value: StoredProfiles {
        get { state.withLock { $0.value } }
        set { state.withLock { $0.value = newValue } }
    }

    var failWrites: Bool {
        get { state.withLock { $0.failWrites } }
        set { state.withLock { $0.failWrites = newValue } }
    }

    func read() throws -> StoredProfiles { value }
    func write(_ profiles: StoredProfiles) throws {
        try state.withLock {
            if $0.failWrites { throw ProfileStorageError() }
            $0.value = profiles
        }
    }
}

private actor PausedProfileRefresh: RefreshOAuthTokenServicing {
    private var started: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<ServerAuthenticationTokens, Never>?
    private var requested = false

    func refreshTokens(serverURL _: URL, refreshToken _: String) async throws -> ServerAuthenticationTokens {
        requested = true
        started?.resume()
        return await withCheckedContinuation { response = $0 }
    }

    func waitForRequest() async {
        if !requested { await withCheckedContinuation { started = $0 } }
    }

    func respond(_ tokens: ServerAuthenticationTokens) { response?.resume(returning: tokens) }
}

private final class ProfileAppStorage: AppStoring, Sendable {
    private struct State {
        var values: [String: Data] = [:]
        var failSigningOut = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    var failSigningOut: Bool {
        get { state.withLock { $0.failSigningOut } }
        set { state.withLock { $0.failSigningOut = newValue } }
    }

    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        try state.withLock {
            try $0.values[key.key].map { try JSONDecoder().decode(Key.Value.self, from: $0) } ?? key.defaultValue
        }
    }

    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        try state.withLock {
            if $0.failSigningOut, key.key == AuthenticationStateKey.key,
               (value as? AuthenticationState) == .loggedOut { throw ProfileStorageError() }
            $0.values[key.key] = try JSONEncoder().encode(value)
        }
    }
}
