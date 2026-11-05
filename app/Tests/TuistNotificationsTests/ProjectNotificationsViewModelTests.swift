import Foundation
import Mockable
import Testing
import TuistServer

@testable import TuistNotifications

@MainActor
@Suite struct ProjectNotificationsViewModelTests {
    private let getPreferencesService = MockGetNotificationPreferencesServicing()
    private let updateProjectService = MockUpdateProjectNotificationServicing()
    private let environmentService = MockServerEnvironmentServicing()
    private let serverURL = URL(string: "https://tuist.dev")!

    private let loaded = ServerNotificationPreferences(
        kind: ServerNotificationPreferences.newPreviewKind,
        accounts: [
            .init(handle: "tuist", enabled: false, projects: [
                .init(handle: "app", setting: .default, enabled: false),
            ]),
        ]
    )

    private func subject() -> ProjectNotificationsViewModel {
        given(environmentService).url().willReturn(serverURL)
        given(getPreferencesService)
            .getNotificationPreferences(kind: .value(ServerNotificationPreferences.newPreviewKind), serverURL: .value(serverURL))
            .willReturn(loaded)
        return ProjectNotificationsViewModel(
            getNotificationPreferencesService: getPreferencesService,
            updateProjectNotificationService: updateProjectService,
            serverEnvironmentService: environmentService
        )
    }

    @Test func finds_the_project_by_its_account_and_project_handles() async throws {
        let subject = subject()

        try await subject.load(fullHandle: "tuist/app")

        #expect(subject.account?.handle == "tuist")
        #expect(subject.project?.setting == .default)
    }

    @Test func has_no_project_outside_the_users_accounts() async throws {
        let subject = subject()

        try await subject.load(fullHandle: "other/app")

        #expect(subject.project == nil)
    }

    @Test func applies_the_change_right_away_and_adopts_the_returned_preferences() async throws {
        let subject = subject()
        try await subject.load(fullHandle: "tuist/app")
        var returned = loaded
        returned.accounts[0].projects[0] = .init(handle: "app", setting: .on, enabled: true)
        // A project created meanwhile, which only the server's response knows about.
        returned.accounts[0].projects.append(.init(handle: "docs", setting: .default, enabled: false))
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .value(ServerNotificationPreferences.newPreviewKind),
                accountHandle: .value("tuist"),
                projectHandle: .value("app"),
                setting: .value(.on),
                serverURL: .value(serverURL)
            )
            .willReturn(returned)

        try await subject.setEnabled(true)

        #expect(subject.preferences == returned)
        #expect(subject.project?.enabled == true)
    }

    @Test func a_failed_change_reverts_and_rethrows() async throws {
        let subject = subject()
        try await subject.load(fullHandle: "tuist/app")
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .any, accountHandle: .any, projectHandle: .any, setting: .any, serverURL: .any
            )
            .willThrow(URLError(.timedOut))

        await #expect(throws: URLError.self) {
            try await subject.setEnabled(true)
        }
        #expect(subject.preferences == loaded)
    }

    @Test func turning_a_project_back_to_its_accounts_value_clears_the_override() async throws {
        var overridden = loaded
        overridden.accounts[0].projects[0] = .init(handle: "app", setting: .on, enabled: true)
        given(environmentService).url().willReturn(serverURL)
        given(getPreferencesService).getNotificationPreferences(kind: .any, serverURL: .any).willReturn(overridden)
        let subject = ProjectNotificationsViewModel(
            getNotificationPreferencesService: getPreferencesService,
            updateProjectNotificationService: updateProjectService,
            serverEnvironmentService: environmentService
        )
        try await subject.load(fullHandle: "tuist/app")
        given(updateProjectService)
            .updateProjectNotificationPreference(
                kind: .any, accountHandle: .any, projectHandle: .any, setting: .value(.default), serverURL: .any
            )
            .willReturn(loaded)

        try await subject.setEnabled(false)

        #expect(subject.project?.setting == .default)
        #expect(subject.project?.enabled == false)
    }

    @Test func summarizes_an_account_by_whether_its_projects_agree() {
        func account(_ enabled: [Bool]) -> ServerNotificationPreferences.Account {
            .init(handle: "tuist", enabled: true, projects: enabled.enumerated().map { index, enabled in
                .init(handle: "p\(index)", setting: enabled ? .default : .off, enabled: enabled)
            })
        }

        #expect(account([true, true]).summary == "On")
        #expect(account([false, false]).summary == "Off")
        #expect(account([true, false]).summary == "Custom")
    }
}
