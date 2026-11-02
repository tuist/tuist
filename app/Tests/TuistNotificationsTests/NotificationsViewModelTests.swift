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
            .init(handle: "tuist", enabled: true, projects: [
                .init(handle: "app", setting: .default, enabled: true),
                .init(handle: "web", setting: .on, enabled: true),
            ]),
        ]
    )

    private func loadedSubject() async throws -> NotificationsViewModel {
        given(environmentService).url().willReturn(serverURL)
        given(listPushDevicesService).listPushDevices(serverURL: .any).willReturn([])
        given(getPreferencesService)
            .getNotificationPreferences(kind: .value(ServerNotificationPreferences.newPreviewKind), serverURL: .value(serverURL))
            .willReturn(loaded)
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
        return subject
    }

    @Test func turning_an_account_off_adopts_the_returned_preferences() async throws {
        let subject = try await loadedSubject()
        var returned = loaded
        returned.accounts[0].enabled = false
        returned.accounts[0].projects[0].enabled = false
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
        returned.accounts[0].projects[0].setting = .off
        returned.accounts[0].projects[0].enabled = false
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .value(ServerNotificationPreferences.newPreviewKind),
                accountHandle: .value("tuist"),
                projectHandle: .value("app"),
                setting: .value(.off),
                serverURL: .value(serverURL)
            )
            .willReturn(returned)

        try await subject.setProjectSetting(.off, accountHandle: "tuist", projectHandle: "app")

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
            try await subject.setProjectSetting(.default, accountHandle: "tuist", projectHandle: "web")
        }
        #expect(subject.newPreviews == loaded)
    }
}
