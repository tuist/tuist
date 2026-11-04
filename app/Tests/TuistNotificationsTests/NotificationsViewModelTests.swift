import Foundation
import Mockable
import Testing
import TuistServer

@testable import TuistNotifications

@MainActor
@Suite struct NotificationsViewModelTests {
    private let getPreferencesService = MockGetNotificationPreferencesServicing()
    private let updateAccountService = MockUpdateAccountNotificationServicing()
    private let updateProjectService = MockUpdateProjectNotificationServicing()
    private let listPushDevicesService = MockListPushDevicesServicing()
    private let environmentService = MockServerEnvironmentServicing()
    private let serverURL = URL(string: "https://tuist.dev")!

    private let loaded = ServerNotificationPreferences(
        kind: ServerNotificationPreferences.newPreviewKind,
        accounts: [
            .init(handle: "marek", enabled: true, projects: []),
            .init(handle: "tuist", enabled: true, projects: [
                .init(handle: "app", setting: .default, enabled: true),
                .init(handle: "web", setting: .on, enabled: true),
            ]),
        ]
    )

    private func loadedSubject(
        updateAccountService: UpdateAccountNotificationServicing? = nil,
        reloadFails: Bool = false
    ) async throws -> NotificationsViewModel {
        given(environmentService).url().willReturn(serverURL)
        given(listPushDevicesService).listPushDevices(serverURL: .any).willReturn([])
        let getPreferences = given(getPreferencesService)
            .getNotificationPreferences(kind: .value(ServerNotificationPreferences.newPreviewKind), serverURL: .value(serverURL))
            .willReturn(loaded)
        if reloadFails {
            getPreferences
                .getNotificationPreferences(
                    kind: .value(ServerNotificationPreferences.newPreviewKind),
                    serverURL: .value(serverURL)
                )
                .willThrow(URLError(.notConnectedToInternet))
        }
        let subject = NotificationsViewModel(
            pushNotifications: PushNotifications(previewPermission: .authorized),
            listPushDevicesService: listPushDevicesService,
            removePushDeviceService: MockRemovePushDeviceServicing(),
            getNotificationPreferencesService: getPreferencesService,
            updateAccountNotificationService: updateAccountService ?? self.updateAccountService,
            updateProjectNotificationService: updateProjectService,
            serverEnvironmentService: environmentService
        )
        try await subject.load()
        return subject
    }

    @Test func turning_an_account_off_adopts_the_returned_preferences() async throws {
        let subject = try await loadedSubject()
        var returned = loaded
        returned.accounts[1].enabled = false
        returned.accounts[1].projects[0].enabled = false
        // A project created meanwhile, which only the server's response knows about.
        returned.accounts[1].projects.append(.init(handle: "docs", setting: .default, enabled: false))
        given(updateAccountService)
            .updateAccountNotificationPreference(
                kind: .value(ServerNotificationPreferences.newPreviewKind),
                accountHandle: .value("tuist"),
                enabled: .value(false),
                serverURL: .value(serverURL)
            )
            .willReturn(returned)

        try await subject.setAccountEnabled(false, accountHandle: "tuist")

        #expect(subject.newPreviews == returned)
    }

    @Test func a_failed_account_change_reverts_and_rethrows() async throws {
        let subject = try await loadedSubject()
        given(updateAccountService)
            .updateAccountNotificationPreference(kind: .any, accountHandle: .any, enabled: .any, serverURL: .any)
            .willThrow(URLError(.notConnectedToInternet))

        await #expect(throws: URLError.self) {
            try await subject.setAccountEnabled(false, accountHandle: "tuist")
        }
        #expect(subject.newPreviews == loaded)
    }

    @Test func a_project_override_adopts_the_returned_preferences() async throws {
        let subject = try await loadedSubject()
        var returned = loaded
        returned.accounts[1].projects[0].setting = .off
        returned.accounts[1].projects[0].enabled = false
        // A project created meanwhile, which only the server's response knows about.
        returned.accounts[1].projects.append(.init(handle: "docs", setting: .default, enabled: true))
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .value(ServerNotificationPreferences.newPreviewKind),
                accountHandle: .value("tuist"),
                projectHandle: .value("app"),
                setting: .value(.off),
                serverURL: .value(serverURL)
            )
            .willReturn(returned)

        try await subject.setProjectEnabled(false, accountHandle: "tuist", projectHandle: "app")

        #expect(subject.newPreviews.account("tuist")?.projects.first?.setting == .off)
        #expect(subject.newPreviews == returned)
    }

    @Test func a_failed_project_change_reverts_and_rethrows() async throws {
        let subject = try await loadedSubject()
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .any, accountHandle: .any, projectHandle: .any, setting: .any, serverURL: .any
            )
            .willThrow(URLError(.timedOut))

        await #expect(throws: URLError.self) {
            try await subject.setProjectEnabled(false, accountHandle: "tuist", projectHandle: "web")
        }
        #expect(subject.newPreviews == loaded)
    }

    @Test func turning_a_project_to_its_accounts_value_clears_the_override() async throws {
        let subject = try await loadedSubject()
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .any, accountHandle: .value("tuist"), projectHandle: .value("web"), setting: .value(.default),
                serverURL: .any
            )
            .willReturn(loaded)

        try await subject.setProjectEnabled(true, accountHandle: "tuist", projectHandle: "web")

        verify(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .any, accountHandle: .any, projectHandle: .any, setting: .value(.default), serverURL: .any
            )
            .called(1)
    }

    @Test func a_failed_change_keeps_a_change_that_was_saved_while_it_was_in_flight() async throws {
        let accountUpdate = SuspendedAccountUpdate()
        let subject = try await loadedSubject(updateAccountService: accountUpdate, reloadFails: true)
        var savedProject = loaded
        savedProject.accounts[1].projects[1].setting = .off
        savedProject.accounts[1].projects[1].enabled = false
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .any, accountHandle: .value("tuist"), projectHandle: .value("web"), setting: .any, serverURL: .any
            )
            .willReturn(savedProject)

        let accountChange = Task { try await subject.setAccountEnabled(false, accountHandle: "tuist") }
        await accountUpdate.waitUntilStarted()
        try await subject.setProjectEnabled(false, accountHandle: "tuist", projectHandle: "web")
        accountUpdate.fail()
        await #expect(throws: URLError.self) { try await accountChange.value }

        // The account change failed and so did the reload, so the screen shows the last state the server confirmed.
        #expect(subject.newPreviews == savedProject)
    }

    @Test func hides_accounts_without_projects() async throws {
        let subject = try await loadedSubject()

        #expect(subject.accountsWithProjects.map(\.handle) == ["tuist"])
    }

    @Test(arguments: [
        GetNotificationPreferencesServiceError.unsupported,
        GetNotificationPreferencesServiceError.forbidden("This can only be managed from a signed-in Tuist app."),
    ])
    func treats_a_server_that_rejects_notifications_as_unsupported(error: GetNotificationPreferencesServiceError) async throws {
        given(environmentService).url().willReturn(serverURL)
        given(listPushDevicesService).listPushDevices(serverURL: .any).willReturn([])
        given(getPreferencesService).getNotificationPreferences(kind: .any, serverURL: .any).willThrow(error)
        let subject = NotificationsViewModel(
            pushNotifications: PushNotifications(previewPermission: .authorized),
            listPushDevicesService: listPushDevicesService,
            removePushDeviceService: MockRemovePushDeviceServicing(),
            getNotificationPreferencesService: getPreferencesService,
            updateAccountNotificationService: updateAccountService,
            updateProjectNotificationService: updateProjectService,
            serverEnvironmentService: environmentService
        )

        try await subject.load()

        #expect(subject.isSupported == false)
    }
}

/// Holds an account change in flight until the test fails it.
private final class SuspendedAccountUpdate: UpdateAccountNotificationServicing, @unchecked Sendable {
    private let started = AsyncStream<Void>.makeStream()
    private let failed = AsyncStream<Void>.makeStream()

    func waitUntilStarted() async {
        for await _ in started.stream {
            return
        }
    }

    func fail() {
        failed.continuation.yield()
    }

    func updateAccountNotificationPreference(
        kind _: String,
        accountHandle _: String,
        enabled _: Bool,
        serverURL _: URL
    ) async throws -> ServerNotificationPreferences {
        started.continuation.yield()
        for await _ in failed.stream {
            break
        }
        throw URLError(.notConnectedToInternet)
    }
}
