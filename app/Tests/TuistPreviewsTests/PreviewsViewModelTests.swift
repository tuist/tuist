import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistServer
import TuistSimulator

@testable import TuistPreviews
@testable import TuistProjects

@MainActor
struct PreviewsViewModelTests {
    private let listProjectsService = MockListProjectsServicing()
    private let listPreviewsService = MockListPreviewsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let appStorage = MockAppStoring()
    private let subject: PreviewsViewModel

    init() {
        subject = PreviewsViewModel(
            projectContext: ProjectContext(
                scope: "test",
                listProjectsService: listProjectsService,
                serverEnvironmentService: serverEnvironmentService,
                appStorage: appStorage
            ),
            listPreviewsService: listPreviewsService,
            serverEnvironmentService: serverEnvironmentService
        )
        given(serverEnvironmentService).url().willReturn(URL(string: "https://tuist.dev")!)
        given(appStorage).get(.any as Parameter<ProjectSelectionsKey.Type>).willReturn([:])
        given(appStorage).set(.any as Parameter<ProjectSelectionsKey.Type>, value: .any).willReturn()
        given(appStorage).get(.any as Parameter<RecentProjectsKey.Type>).willReturn([:])
        given(appStorage).set(.any as Parameter<RecentProjectsKey.Type>, value: .any).willReturn()
    }

    @Test func recent_previews_are_limited_to_three_newest_without_limiting_the_browser() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPreviews(
            (1 ... 8).reversed().map { .test(id: "\($0)", insertedAt: Date(timeIntervalSince1970: Double($0))) },
            fullHandle: "tuist/app"
        )

        try await subject.onAppear()

        #expect(subject.recentPreviews.map(\.id) == ["8", "7", "6"])
        #expect(subject.previews.count == 8)
    }

    @Test func selected_project_is_shared_by_home_and_previews() async throws {
        let first = ServerProject.test(fullName: "tuist/first")
        let second = ServerProject.test(fullName: "tuist/second")
        given(listProjectsService).listProjects(serverURL: .any).willReturn([first, second])
        stubPreviews([.test(id: "first")], fullHandle: first.fullName)
        stubPreviews([.test(id: "second")], fullHandle: second.fullName)

        try await subject.onAppear()
        try await subject.selectProject(second)

        #expect(subject.selectedProject?.fullName == second.fullName)
        #expect(subject.recentPreviews.map(\.id) == ["second"])
        #expect(subject.previews == subject.recentPreviews)
    }

    @Test func shell_selection_hides_previous_project_data_before_reloading() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([
            .test(fullName: "tuist/first"), .test(fullName: "tuist/second"),
        ])
        stubPreviews([.test(id: "first")], fullHandle: "tuist/first")
        stubPreviews([.test(id: "second")], fullHandle: "tuist/second")
        try await subject.onAppear()

        subject.projectContext.selectProject("tuist/second")
        #expect(subject.recentPreviews.isEmpty)
        #expect(subject.previews.isEmpty)

        try await subject.loadSelectedProject()
        #expect(subject.recentPreviews.map(\.id) == ["second"])
    }

    @Test func refreshing_projects_preserves_the_shell_selection() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([
            .test(fullName: "tuist/first"), .test(fullName: "tuist/second"),
        ])
        stubPreviews([.test(id: "first")], fullHandle: "tuist/first")
        stubPreviews([.test(id: "second")], fullHandle: "tuist/second")
        try await subject.onAppear()
        subject.projectContext.selectProject("tuist/second")

        try await subject.refreshProjects()

        #expect(subject.selectedProject?.fullName == "tuist/second")
        #expect(subject.recentPreviews.map(\.id) == ["second"])
    }

    @Test func no_projects_has_no_recent_previews() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([])

        try await subject.onAppear()

        #expect(subject.recentPreviews.isEmpty)
        #expect(subject.selectedProject == nil)
        #expect(!subject.isInitialLoading)
    }

    @Test func project_without_previews_has_no_recent_previews() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPreviews([], fullHandle: "tuist/app")

        try await subject.onAppear()

        #expect(subject.recentPreviews.isEmpty)
        #expect(subject.selectedProject != nil)
        #expect(!subject.isInitialLoading)
    }

    @Test func refreshing_an_empty_project_keeps_the_loaded_list_mounted() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        let service = InspectingPreviewsService()
        let subject = PreviewsViewModel(
            projectContext: subject.projectContext,
            listPreviewsService: service,
            serverEnvironmentService: serverEnvironmentService
        )
        try await subject.onAppear()
        service.onRequest = {
            #expect(subject.isRefreshingPreviews)
            #expect(!subject.isInitialLoading)
        }
        defer { service.onRequest = nil }

        try await subject.refreshPreviews()

        #expect(!subject.isInitialLoading)
        #expect(!subject.isRefreshingPreviews)
    }

    @Test func retrying_a_failed_first_page_keeps_the_refreshing_list_mounted() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        let service = InspectingPreviewsService()
        service.fails = true
        let subject = PreviewsViewModel(
            projectContext: subject.projectContext,
            listPreviewsService: service,
            serverEnvironmentService: serverEnvironmentService
        )
        await #expect(throws: PreviewLoadError.self) { try await subject.onAppear() }
        service.fails = false
        service.onRequest = {
            #expect(subject.isRefreshingPreviews)
            #expect(!subject.isInitialLoading)
        }
        defer { service.onRequest = nil }

        try await subject.refreshPreviews()

        #expect(!subject.isInitialLoading)
        #expect(!subject.isRefreshingPreviews)
    }

    private func stubPreviews(_ previews: [ServerPreview], fullHandle: String) {
        given(listPreviewsService)
            .listPreviews(
                displayName: .any,
                specifier: .any,
                supportedPlatforms: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .value(fullHandle),
                serverURL: .any
            )
            .willReturn(.test(previews: previews))
    }
}

@MainActor
private final class InspectingPreviewsService: ListPreviewsServicing {
    var onRequest: (() -> Void)?
    var fails = false

    func listPreviews(
        displayName _: String?,
        specifier _: String?,
        supportedPlatforms _: [DestinationType],
        page _: Int?,
        pageSize _: Int?,
        distinctField _: ListPreviewsDistinctField?,
        fullHandle _: String,
        serverURL _: URL
    ) async throws -> ServerPreviewsPage {
        onRequest?()
        if fails { throw PreviewLoadError.failed }
        return .test(previews: [])
    }
}

private enum PreviewLoadError: Error {
    case failed
}
