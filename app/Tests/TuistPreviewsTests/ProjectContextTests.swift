import Foundation
import Mockable
import Synchronization
import Testing
import TuistAppStorage
import TuistServer

@testable import TuistProjects

@MainActor
struct ProjectContextTests {
    private let projects = [
        ServerProject.test(id: 1, fullName: "tuist/app"),
        ServerProject.test(id: 2, fullName: "tuist/cli"),
        ServerProject.test(id: 3, fullName: "other/mobile"),
    ]
    private let listProjectsService = MockListProjectsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let storage = MemoryProjectStorage()

    init() {
        given(serverEnvironmentService).url().willReturn(URL(string: "https://tuist.dev")!)
        given(listProjectsService).listProjects(serverURL: .any).willReturn(projects)
    }

    @Test func initial_selection_and_recents_are_shared_without_feature_dependencies() async throws {
        let context = makeContext()
        try await context.load()
        context.selectProject("tuist/cli")
        context.selectProject("other/mobile")
        context.selectProject("tuist/cli")

        #expect(context.selectedFullHandle == "tuist/cli")
        #expect(context.recentProjects.map(\.fullName) == ["tuist/cli", "other/mobile", "tuist/app"])
        #expect(!context.isLoading)
    }

    @Test func quick_switcher_prioritizes_selection_and_recents_without_duplicates() async throws {
        let context = makeContext()
        #expect(context.switcherProjects.isEmpty)
        try await context.load()
        context.selectProject("tuist/cli")
        context.selectProject("other/mobile")

        #expect(context.switcherProjects.map(\.fullName) == ["other/mobile", "tuist/cli", "tuist/app"])
    }

    @Test func quick_switcher_is_bounded_without_truncating_project_discovery() async throws {
        let available = (0 ..< 10).map { ServerProject.test(id: $0, fullName: "tuist/project-\($0)") }
        let service = ChangingProjectsService(projects: available)
        let context = makeContext(service: service)
        try await context.load()
        context.selectProject("tuist/project-8")
        context.selectProject("tuist/project-9")

        #expect(context.switcherProjects.map(\.fullName) == [
            "tuist/project-9", "tuist/project-8", "tuist/project-0", "tuist/project-1", "tuist/project-2",
        ])
        #expect(context.projects.count == 10)
        #expect(context.projects(matching: "project-7").map(\.fullName) == ["tuist/project-7"])
    }

    @Test func selection_is_restored_for_the_same_server_and_account() async throws {
        let first = makeContext()
        try await first.load()
        first.selectProject("tuist/cli")
        let restored = makeContext()

        try await restored.load()

        #expect(restored.selectedFullHandle == "tuist/cli")
        #expect(restored.recentFullHandles == ["tuist/cli", "tuist/app"])
    }

    @Test(arguments: ["https://other.example/alice", "https://tuist.dev/bob"])
    func another_server_or_account_does_not_inherit_selection(scope: String) async throws {
        let first = makeContext()
        try await first.load()
        first.selectProject("tuist/cli")
        let other = makeContext(scope: scope)

        try await other.load()

        #expect(other.selectedFullHandle == "tuist/app")
        #expect(other.recentFullHandles == ["tuist/app"])
        #expect(try storage.get(ProjectSelectionsKey.self)["https://tuist.dev/alice"] == "tuist/cli")
    }

    @Test func windows_keep_independent_live_selections() async throws {
        let first = makeContext()
        let second = makeContext()
        try await first.load()
        try await second.load()

        first.selectProject("tuist/cli")

        #expect(first.selectedFullHandle == "tuist/cli")
        #expect(second.selectedFullHandle == "tuist/app")
    }

    @Test func removed_projects_fall_back_and_an_empty_account_clears_selection() async throws {
        let service = ChangingProjectsService(projects: projects)
        let context = makeContext(service: service)
        try await context.load()
        context.selectProject("tuist/cli")
        service.projects = [projects[2]]

        try await context.refresh()
        #expect(context.selectedFullHandle == "other/mobile")
        #expect(context.recentProjects.map(\.fullName) == ["other/mobile"])
        #expect(context.switcherProjects.map(\.fullName) == ["other/mobile"])

        service.projects = []
        try await context.refresh()
        #expect(context.selectedProject == nil)
        #expect(context.recentProjects.isEmpty)
        #expect(context.switcherProjects.isEmpty)
        #expect(try storage.get(ProjectSelectionsKey.self)["https://tuist.dev/alice"] == nil)
    }

    @Test func search_matches_organization_and_project_case_insensitively() async throws {
        let context = makeContext()
        try await context.load()

        #expect(context.projects(matching: " TUIST ").map(\.fullName) == ["tuist/app", "tuist/cli"])
        #expect(context.projects(matching: "MOBILE").map(\.fullName) == ["other/mobile"])
        #expect(context.projects(matching: "missing").isEmpty)
        #expect(context.projects(matching: " ").count == 3)
    }

    @Test func a_failure_is_visible_and_can_be_retried() async throws {
        let service = ChangingProjectsService(projects: projects)
        service.error = URLError(.notConnectedToInternet)
        let context = makeContext(service: service)
        await #expect(throws: URLError.self) { try await context.load() }
        #expect(context.errorMessage != nil)
        #expect(!context.isLoading)

        service.error = nil
        try await context.load()
        #expect(context.errorMessage == nil)
        #expect(context.selectedFullHandle == "tuist/app")
    }

    @Test func an_unknown_project_does_not_replace_the_context() async throws {
        let context = makeContext()
        try await context.load()

        context.selectProject("unknown/project")

        #expect(context.selectedFullHandle == "tuist/app")
    }

    private func makeContext(
        scope: String = "https://tuist.dev/alice",
        service: ListProjectsServicing? = nil
    ) -> ProjectContext {
        ProjectContext(
            scope: scope,
            listProjectsService: service ?? listProjectsService,
            serverEnvironmentService: serverEnvironmentService,
            appStorage: storage
        )
    }
}

@MainActor
private final class ChangingProjectsService: ListProjectsServicing {
    var projects: [ServerProject]
    var error: URLError?

    init(projects: [ServerProject]) {
        self.projects = projects
    }

    func listProjects(serverURL _: URL) async throws -> [ServerProject] {
        if let error { throw error }
        return projects
    }

    func listProjects(serverURL: URL, accountName _: String?, projectName _: String?) async throws -> [ServerProject] {
        try await listProjects(serverURL: serverURL)
    }
}

private final class MemoryProjectStorage: AppStoring {
    private let values = Mutex<[String: Data]>([:])

    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        try values.withLock { values in
            guard let data = values[key.key] else { return key.defaultValue }
            return try JSONDecoder().decode(Key.Value.self, from: data)
        }
    }

    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        try values.withLock { values in values[key.key] = try JSONEncoder().encode(value) }
    }
}
