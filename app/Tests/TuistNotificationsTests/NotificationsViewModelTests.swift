import Foundation
import Mockable
import Testing
import TuistServer

@testable import TuistNotifications

@MainActor
@Suite struct NotificationsViewModelTests {
    private let rulesService = MockNotificationRulesServicing()
    private let listPushDevicesService = MockListPushDevicesServicing()
    private let listProjectsService = MockListProjectsServicing()
    private let environmentService = MockServerEnvironmentServicing()
    private let serverURL = URL(string: "https://tuist.dev")!

    private let betaRule = ServerNotificationRule(id: "rule-1", projects: ["tuist/ios-app"], track: .is("beta"))

    private func loadedSubject(rules: [ServerNotificationRule]) async throws -> NotificationsViewModel {
        given(environmentService).url().willReturn(serverURL)
        given(listPushDevicesService).listPushDevices(serverURL: .any).willReturn([])
        given(listProjectsService).listProjects(serverURL: .any).willReturn([
            .test(fullName: "tuist/ios-app"),
            .test(fullName: "acme/shop"),
        ])
        given(rulesService).listRules(serverURL: .value(serverURL)).willReturn(rules)
        let subject = NotificationsViewModel(
            pushNotifications: PushNotifications(previewPermission: .authorized),
            notificationRulesService: rulesService,
            listPushDevicesService: listPushDevicesService,
            removePushDeviceService: MockRemovePushDeviceServicing(),
            listProjectsService: listProjectsService,
            serverEnvironmentService: environmentService
        )
        try await subject.load()
        return subject
    }

    @Test func loads_rules_and_sorted_projects() async throws {
        let subject = try await loadedSubject(rules: [betaRule])

        #expect(subject.didLoad)
        #expect(subject.rules == [betaRule])
        #expect(subject.projects == ["acme/shop", "tuist/ios-app"])
    }

    @Test func a_new_rule_is_created_and_appended_with_the_server_id() async throws {
        let subject = try await loadedSubject(rules: [betaRule])
        let draft = ServerNotificationRule(gitBranch: .contains("release/"))
        var created = draft
        created.id = "rule-2"
        given(rulesService).createRule(.value(draft), serverURL: .value(serverURL)).willReturn(created)

        try await subject.save(draft)

        #expect(subject.rules.map(\.id) == ["rule-1", "rule-2"])
        verify(rulesService).updateRule(.any, serverURL: .any).called(0)
    }

    @Test func an_existing_rule_is_updated_in_place_with_what_the_server_saved() async throws {
        let subject = try await loadedSubject(rules: [betaRule])
        var edited = betaRule
        edited.isEnabled = false
        // The server normalizes values, so its response wins over the local edit.
        var saved = edited
        saved.track = .is("Beta")
        given(rulesService).updateRule(.value(edited), serverURL: .value(serverURL)).willReturn(saved)

        try await subject.setEnabled(false, rule: betaRule)

        #expect(subject.rules == [saved])
        #expect(subject.rulesInFlight.isEmpty)
    }

    @Test func a_failed_update_keeps_the_rule_as_it_was() async throws {
        let subject = try await loadedSubject(rules: [betaRule])
        given(rulesService).updateRule(.any, serverURL: .any).willThrow(URLError(.notConnectedToInternet))

        await #expect(throws: URLError.self) { try await subject.setEnabled(false, rule: betaRule) }

        #expect(subject.rules == [betaRule])
        #expect(subject.rulesInFlight.isEmpty)
    }

    @Test func condition_options_merge_the_rule_projects_and_skip_any_project_rules() async throws {
        let subject = try await loadedSubject(rules: [])
        given(rulesService)
            .conditionOptions(event: .any, projectFullHandle: .value("tuist/ios-app"), serverURL: .any)
            .willReturn(["track": ["beta", "internal"]])
        given(rulesService)
            .conditionOptions(event: .any, projectFullHandle: .value("acme/shop"), serverURL: .any)
            .willReturn(["track": ["beta", "qa"]])

        let tracks = await subject.options(
            for: "track",
            in: ServerNotificationRule(projects: ["tuist/ios-app", "acme/shop"])
        )
        let anyProject = await subject.options(for: "track", in: ServerNotificationRule())

        #expect(tracks == ["beta", "internal", "qa"])
        #expect(anyProject.isEmpty)
    }

    @Test func servers_without_rules_are_unsupported() async throws {
        given(environmentService).url().willReturn(serverURL)
        given(listPushDevicesService).listPushDevices(serverURL: .any).willReturn([])
        given(listProjectsService).listProjects(serverURL: .any).willReturn([])
        given(rulesService).listRules(serverURL: .any).willThrow(NotificationRulesServiceError.unsupported)
        let subject = NotificationsViewModel(
            pushNotifications: PushNotifications(previewPermission: .authorized),
            notificationRulesService: rulesService,
            listPushDevicesService: listPushDevicesService,
            removePushDeviceService: MockRemovePushDeviceServicing(),
            listProjectsService: listProjectsService,
            serverEnvironmentService: environmentService
        )

        try await subject.load()

        #expect(!subject.isSupported)
    }
}
