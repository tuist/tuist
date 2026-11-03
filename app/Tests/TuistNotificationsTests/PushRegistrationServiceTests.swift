import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistServer

@testable import TuistNotifications

@Suite struct PushRegistrationServiceTests {
    private let registerService = MockRegisterPushDeviceServicing()
    private let unregisterService = MockUnregisterPushDeviceServicing()
    private let appStorage = InMemoryAppStorage()
    private let installationIDs = InstallationIDs()
    private let serverURL = URL(string: "https://tuist.dev")!
    private let selfHostedURL = URL(string: "https://tuist.example.com")!

    private var subject: PushRegistrationService {
        PushRegistrationService(
            registerPushDeviceService: registerService,
            unregisterPushDeviceService: unregisterService,
            appStorage: appStorage,
            makeInstallationID: installationIDs.next
        )
    }

    private func givenRegistration(failing failures: [String: RegisterPushDeviceServiceError] = [:]) {
        given(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .willProduce { installationID, _, _, _, _ in
                if let error = failures[installationID] { throw error }
                return "registration-\(installationID)"
            }
    }

    private func optIn(serverURL: URL? = nil) async throws {
        try await subject.setEnabled(true, serverURL: serverURL ?? self.serverURL)
    }

    private func register(serverURL: URL? = nil) async throws {
        try await subject.register(
            token: "abc123",
            environment: .sandbox,
            name: "iPhone 17 Pro",
            serverURL: serverURL ?? self.serverURL
        )
    }

    @Test func does_not_register_until_notifications_are_turned_on() async throws {
        givenRegistration()

        try await register()

        #expect(subject.isEnabled(serverURL: serverURL) == false)
        #expect(subject.installationID(serverURL: serverURL) == nil)
        verify(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .called(0)
    }

    @Test func registers_with_a_new_installation_id_and_reuses_it() async throws {
        givenRegistration()
        try await optIn()

        try await register()
        try await register()

        #expect(subject.installationID(serverURL: serverURL) == "id-1")
        verify(registerService)
            .registerPushDevice(
                installationID: .value("id-1"),
                token: .value("abc123"),
                environment: .value(.sandbox),
                name: .value("iPhone 17 Pro"),
                serverURL: .value(serverURL)
            )
            .called(2)
    }

    @Test func keeps_installation_ids_per_server() async throws {
        givenRegistration()
        try await optIn()
        try await optIn(serverURL: selfHostedURL)

        try await register()
        try await register(serverURL: selfHostedURL)

        #expect(subject.installationID(serverURL: serverURL) == "id-1")
        #expect(subject.installationID(serverURL: selfHostedURL) == "id-2")
    }

    @Test(arguments: [
        RegisterPushDeviceServiceError.retired("retired"),
        RegisterPushDeviceServiceError.conflict("conflict"),
    ])
    func rotates_the_installation_id_and_retries_once(error: RegisterPushDeviceServiceError) async throws {
        givenRegistration(failing: ["id-1": error])
        try await optIn()

        try await register()

        #expect(subject.installationID(serverURL: serverURL) == "id-2")
        #expect(subject.isEnabled(serverURL: serverURL))
        verify(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .called(2)
    }

    @Test func gives_up_when_the_rotated_installation_id_also_fails() async throws {
        givenRegistration(failing: ["id-1": .retired("retired"), "id-2": .retired("retired")])
        try await optIn()

        await #expect(throws: RegisterPushDeviceServiceError.retired("retired")) {
            try await register()
        }
        verify(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .called(2)
    }

    @Test func skips_registration_quietly_when_the_server_does_not_support_push() async throws {
        givenRegistration(failing: ["id-1": .unsupported])
        try await optIn()

        try await register()

        #expect(subject.installationID(serverURL: serverURL) == "id-1")
        #expect(subject.isEnabled(serverURL: serverURL))
        verify(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .called(1)
    }

    @Test func turns_notifications_off_when_the_device_was_removed() async throws {
        givenRegistration(failing: ["id-1": .removed("removed")])
        try await optIn()

        try await register()
        try await register()

        #expect(subject.isEnabled(serverURL: serverURL) == false)
        #expect(subject.installationID(serverURL: serverURL) == nil)
        verify(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .called(1)
    }

    @Test func turning_notifications_back_on_registers_a_new_installation() async throws {
        givenRegistration(failing: ["id-1": .removed("removed")])
        try await optIn()
        try await register()

        try await subject.setEnabled(true, serverURL: serverURL)
        try await register()

        #expect(subject.isEnabled(serverURL: serverURL))
        #expect(subject.installationID(serverURL: serverURL) == "id-2")
    }

    @Test func turning_notifications_off_unregisters_the_installation() async throws {
        givenRegistration()
        given(unregisterService).unregisterPushDevice(installationID: .any, serverURL: .any).willReturn()
        try await optIn()
        try await register()

        try await subject.setEnabled(false, serverURL: serverURL)
        try await register()

        #expect(subject.isEnabled(serverURL: serverURL) == false)
        #expect(subject.installationID(serverURL: serverURL) == nil)
        verify(unregisterService).unregisterPushDevice(installationID: .value("id-1"), serverURL: .value(serverURL)).called(1)
        verify(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .called(1)
    }

    @Test func turning_notifications_off_keeps_them_on_when_unregistering_fails() async throws {
        givenRegistration()
        given(unregisterService).unregisterPushDevice(installationID: .any, serverURL: .any)
            .willThrow(URLError(.notConnectedToInternet))
        try await optIn()
        try await register()

        await #expect(throws: URLError.self) {
            try await subject.setEnabled(false, serverURL: serverURL)
        }

        #expect(subject.isEnabled(serverURL: serverURL))
        #expect(subject.installationID(serverURL: serverURL) == "id-1")
    }

    @Test func signing_out_forgets_the_installation_even_if_unregistering_fails() async throws {
        givenRegistration()
        given(unregisterService).unregisterPushDevice(installationID: .any, serverURL: .any)
            .willThrow(URLError(.notConnectedToInternet))
        try await optIn()
        try await optIn(serverURL: selfHostedURL)
        try await register()
        try await register(serverURL: selfHostedURL)

        await subject.signOut(serverURL: serverURL)

        #expect(subject.installationID(serverURL: serverURL) == nil)
        #expect(subject.isEnabled(serverURL: serverURL) == false)
        #expect(subject.installationID(serverURL: selfHostedURL) == "id-2")
        verify(unregisterService).unregisterPushDevice(installationID: .value("id-1"), serverURL: .value(serverURL)).called(1)
    }

    @Test func forgetting_all_installations_opts_every_server_out() async throws {
        givenRegistration()
        try await optIn()
        try await optIn(serverURL: selfHostedURL)
        try await register()

        subject.forgetAll()
        try await register()

        #expect(subject.isEnabled(serverURL: serverURL) == false)
        #expect(subject.isEnabled(serverURL: selfHostedURL) == false)
        #expect(subject.installationID(serverURL: serverURL) == nil)
        verify(registerService)
            .registerPushDevice(installationID: .any, token: .any, environment: .any, name: .any, serverURL: .any)
            .called(1)
    }
}

private final class InMemoryAppStorage: AppStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        guard let data = lock.withLock({ values[key.key] }) else { return key.defaultValue }
        return try JSONDecoder().decode(Key.Value.self, from: data)
    }

    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        let data = try JSONEncoder().encode(value)
        lock.withLock { values[key.key] = data }
    }
}

private final class InstallationIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> String {
        lock.withLock {
            count += 1
            return "id-\(count)"
        }
    }
}
