import AppKit
import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistServer
import TuistSimulator

@testable import TuistMenuBar
@testable import TuistProjects

@MainActor
struct DesktopPreviewsModelTests {
    private let listProjectsService = MockListProjectsServicing()
    private let listPreviewsService = MockListPreviewsServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let appStorage = MockAppStoring()
    private let subject: DesktopPreviewsModel

    init() {
        given(serverEnvironmentService).url().willReturn(URL(string: "https://tuist.dev")!)
        given(appStorage).get(.any as Parameter<ProjectSelectionsKey.Type>).willReturn([:])
        given(appStorage).set(.any as Parameter<ProjectSelectionsKey.Type>, value: .any).willReturn()
        given(appStorage).get(.any as Parameter<RecentProjectsKey.Type>).willReturn([:])
        given(appStorage).set(.any as Parameter<RecentProjectsKey.Type>, value: .any).willReturn()
        subject = DesktopPreviewsModel(
            projectContext: ProjectContext(
                scope: "test",
                listProjectsService: listProjectsService,
                serverEnvironmentService: serverEnvironmentService,
                appStorage: appStorage
            ),
            listPreviewsService: listPreviewsService,
            serverEnvironmentService: serverEnvironmentService
        )
    }

    @Test func home_shows_three_newest_and_browser_keeps_all_previews() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPage((1 ... 8).reversed().map { .test(id: "\($0)", insertedAt: Date(timeIntervalSince1970: Double($0))) })

        try await subject.refresh()

        #expect(subject.recentPreviews.map(\.id) == ["8", "7", "6"])
        #expect(subject.filteredPreviews.count == 8)
        #expect(!subject.isLoading)
    }

    @Test func shell_selection_hides_previous_project_data_before_reloading() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([
            .test(fullName: "tuist/app"), .test(fullName: "tuist/other"),
        ])
        stubPage([.test(id: "first")])
        stubPage([.test(id: "second")], fullHandle: "tuist/other")
        try await subject.refresh()

        subject.projectContext.selectProject("tuist/other")
        #expect(subject.previews.isEmpty)

        try await subject.loadSelectedProject()
        #expect(subject.previews.map(\.id) == ["second"])
    }

    @Test func picker_requests_keep_the_contexts_credentials_and_cache() async throws {
        let credentials = MockServerCredentialsStoring()
        let cache = MockCachedValueStoring()
        given(listProjectsService).listProjects(serverURL: .any).willProduce { _ in
            #expect((ServerCredentialsStore.current as AnyObject) === credentials)
            #expect((CachedValueStore.current as AnyObject) === cache)
            return [.test(fullName: "tuist/app")]
        }
        let context = ServerCredentialsStore.$current.withValue(credentials) {
            CachedValueStore.$current.withValue(cache) {
                ProjectContext(
                    scope: "test",
                    listProjectsService: listProjectsService,
                    serverEnvironmentService: serverEnvironmentService,
                    appStorage: appStorage
                )
            }
        }

        try await context.load()

        #expect(context.selectedFullHandle == "tuist/app")
    }

    @Test func no_projects_clears_the_selection_and_previews() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([])

        try await subject.refresh()

        #expect(subject.projects.isEmpty)
        #expect(subject.previews.isEmpty)
        #expect(subject.selectedProjectFullHandle == nil)
        #expect(!subject.hasMorePreviews)
        #expect(!subject.isLoading)
    }

    @Test func selecting_a_project_resets_data_and_search() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([
            .test(fullName: "tuist/app"), .test(fullName: "tuist/other"),
        ])
        stubPage([.test(id: "first")])
        stubPage([.test(id: "second")], fullHandle: "tuist/other")
        try await subject.refresh()
        subject.searchText = "first"
        subject.trackFilter = .track("beta")

        try await subject.selectProject("tuist/other")

        #expect(subject.selectedProjectFullHandle == "tuist/other")
        #expect(subject.previews.map(\.id) == ["second"])
        #expect(subject.searchText.isEmpty)
        #expect(subject.trackFilter == .all)
    }

    @Test func browser_filters_names_branches_and_commits_case_insensitively() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPage([
            .test(id: "1", displayName: "Tuist", gitCommitSHA: "abcdef", gitBranch: "feature/home"),
            .test(id: "2", bundleIdentifier: "dev.other.app", displayName: "Other", gitCommitSHA: "123456", gitBranch: "main"),
        ])
        try await subject.refresh()

        for query in [" TUIST ", "FEATURE/HOME", "ABCDEF"] {
            subject.searchText = query
            #expect(subject.filteredPreviews.map(\.id) == ["1"])
        }
        subject.searchText = "missing"
        #expect(subject.filteredPreviews.isEmpty)
        subject.searchText = ""
        #expect(subject.filteredPreviews.count == 2)
    }

    @Test func track_filters_combine_with_search_without_filtering_home() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPage([
            .test(id: "beta", displayName: "Tuist", track: "beta"),
            .test(id: "nightly", displayName: "Tuist", track: "nightly"),
            .test(id: "none", displayName: "Other"),
            .test(id: "empty", displayName: "Other", track: ""),
        ])
        try await subject.refresh()

        #expect(subject.availableTracks == ["beta", "nightly"])
        subject.trackFilter = .track("beta")
        #expect(subject.filteredPreviews.map(\.id) == ["beta"])
        #expect(subject.recentPreviews.map(\.id) == ["beta", "nightly", "none"])
        subject.searchText = "other"
        #expect(subject.filteredPreviews.isEmpty)
        subject.trackFilter = .unassigned
        #expect(subject.filteredPreviews.map(\.id) == ["none", "empty"])
        subject.clearFilters()
        #expect(!subject.hasActiveFilters)
        #expect(subject.filteredPreviews.count == 4)
        subject.searchText = " NIGHTLY "
        #expect(subject.filteredPreviews.map(\.id) == ["nightly"])
    }

    @Test func loading_more_expands_track_choices_and_keeps_the_active_filter() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPage([.test(id: "first", track: "beta")], hasNextPage: true)
        stubPage([.test(id: "second", track: "nightly"), .test(id: "third", track: "beta")], page: 2)
        try await subject.refresh()
        subject.trackFilter = .track("beta")

        try await subject.loadMore()

        #expect(subject.availableTracks == ["beta", "nightly"])
        #expect(subject.trackFilter == .track("beta"))
        #expect(subject.filteredPreviews.map(\.id) == ["first", "third"])
    }

    @Test func a_track_without_current_matches_remains_a_valid_picker_selection() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPage([.test(id: "preview", track: "nightly")])
        try await subject.refresh()
        subject.trackFilter = .track("beta")

        #expect(subject.availableTracks == ["beta", "nightly"])
        #expect(subject.filteredPreviews.isEmpty)
        subject.clearFilters()
        #expect(subject.availableTracks == ["nightly"])
    }

    @Test func server_preview_preserves_track_metadata_and_legacy_cached_previews() throws {
        let payload = Components.Schemas.Preview(
            builds: [],
            created_from_ci: false,
            device_url: "https://tuist.dev/device",
            icon_url: "https://tuist.dev/icon.png",
            id: "preview",
            inserted_at: "2026-10-16T00:00:00Z",
            qr_code_url: "https://tuist.dev/qr.png",
            supported_platforms: [],
            track: "beta",
            url: "https://tuist.dev/preview"
        )
        let preview = try ServerPreview(payload)
        #expect(preview.track == "beta")
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preview)) as? [String: Any])
        legacy.removeValue(forKey: "track")
        let decoded = try JSONDecoder().decode(ServerPreview.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.track == nil)
    }

    @Test func browser_loads_the_next_page() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "tuist/app")])
        stubPage([.test(id: "first")], hasNextPage: true)
        stubPage([.test(id: "second")], page: 2)
        try await subject.refresh()

        try await subject.loadMore()

        #expect(subject.previews.map(\.id) == ["first", "second"])
        #expect(!subject.hasMorePreviews)
        #expect(!subject.isLoadingMore)
    }

    @Test func loading_failure_leaves_a_retryable_state() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willThrow(URLError(.notConnectedToInternet))

        await #expect(throws: URLError.self) { try await subject.refresh() }

        #expect(subject.errorMessage != nil)
        #expect(!subject.isLoading)
    }

    @Test func late_page_from_previous_project_is_discarded() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([
            .test(fullName: "tuist/app"), .test(fullName: "tuist/other"),
        ])
        stubPage([.test(id: "first")], hasNextPage: true)
        stubPage([.test(id: "other")], fullHandle: "tuist/other")
        let pendingPage = PendingPage()
        let subject = DesktopPreviewsModel(
            projectContext: subject.projectContext,
            listPreviewsService: SuspendedPageService(base: listPreviewsService, pendingPage: pendingPage),
            serverEnvironmentService: serverEnvironmentService
        )
        try await subject.refresh()
        let loadingTask = Task { try await subject.loadMore() }
        await pendingPage.waitUntilRequested()

        try await subject.selectProject("tuist/other")
        await pendingPage.resume(with: .test(previews: [.test(id: "stale")]))
        try await loadingTask.value

        #expect(subject.selectedProjectFullHandle == "tuist/other")
        #expect(subject.previews.map(\.id) == ["other"])
        #expect(!subject.isLoadingMore)
    }

    @Test func returning_to_a_project_while_another_is_loading_restores_pagination() async throws {
        given(listProjectsService).listProjects(serverURL: .any).willReturn([
            .test(fullName: "tuist/app"), .test(fullName: "tuist/other"),
        ])
        stubPage([.test(id: "first")], hasNextPage: true)
        let pendingPage = PendingPage()
        let subject = DesktopPreviewsModel(
            projectContext: subject.projectContext,
            listPreviewsService: SuspendedPageService(
                base: listPreviewsService,
                pendingPage: pendingPage,
                pendingFirstPageFullHandle: "tuist/other"
            ),
            serverEnvironmentService: serverEnvironmentService
        )
        try await subject.refresh()
        let loadingTask = Task { try await subject.selectProject("tuist/other") }
        await pendingPage.waitUntilRequested()

        try await subject.selectProject("tuist/app")
        await pendingPage.resume(with: .test(previews: [.test(id: "stale")]))
        try await loadingTask.value

        #expect(subject.selectedProjectFullHandle == "tuist/app")
        #expect(subject.previews.map(\.id) == ["first"])
        #expect(subject.hasMorePreviews)
        #expect(!subject.isLoading)
    }

    @Test(arguments: [
        "tuist:open-preview?preview_id=123&full_handle=tuist/app&server_url=https://tuist.dev",
        "tuist://open-preview?preview_id=123&full_handle=tuist/app&server_url=https://tuist.dev",
    ])
    func preview_links_are_recognized(url: String) throws {
        #expect(MacApplicationModel.isPreviewDeepLink(try #require(URL(string: url))))
    }

    @Test(arguments: ["tuist://oauth-callback?code=123", "https://tuist.dev/tuist/app/previews/123"])
    func unrelated_links_are_not_installed(url: String) throws {
        #expect(!MacApplicationModel.isPreviewDeepLink(try #require(URL(string: url))))
    }

    @Test func closing_the_window_does_not_quit_the_app() {
        let delegate = AppDelegate()
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @Test func dock_reopen_restores_the_window_only_when_needed() {
        let delegate = AppDelegate()
        var openedWindows = 0
        delegate.openMainWindow = { openedWindows += 1 }

        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        #expect(openedWindows == 1)
        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        #expect(openedWindows == 1)
    }

    @Test func app_actions_use_the_shared_credentials_store_without_changing_the_callers_store() async {
        let outsideStore = MockServerCredentialsStoring()
        await ServerCredentialsStore.$current.withValue(outsideStore) {
            let first = await MacApplicationEnvironment.withValue { () async in ServerCredentialsStore.current }
            let second = await MacApplicationEnvironment.withValue { () async in ServerCredentialsStore.current }
            #expect(first is ServerCredentialsStore)
            #expect((first as AnyObject) === (second as AnyObject))
            #expect(ServerCredentialsStore.current is MockServerCredentialsStoring)
        }
    }

    private func stubPage(
        _ previews: [ServerPreview],
        fullHandle: String = "tuist/app",
        page: Int = 1,
        hasNextPage: Bool = false
    ) {
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .any, supportedPlatforms: .any,
                page: .value(page), pageSize: .any, distinctField: .any,
                fullHandle: .value(fullHandle), serverURL: .any
            )
            .willReturn(.test(previews: previews, paginationMetadata: .test(hasNextPage: hasNextPage, currentPage: page)))
    }
}

private struct SuspendedPageService: ListPreviewsServicing {
    let base: ListPreviewsServicing
    let pendingPage: PendingPage
    var pendingFirstPageFullHandle: String?

    func listPreviews(
        displayName: String?,
        specifier: String?,
        supportedPlatforms: [DestinationType],
        page: Int?,
        pageSize: Int?,
        distinctField: ListPreviewsDistinctField?,
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerPreviewsPage {
        if (page == 2 && fullHandle == "tuist/app") || (page == 1 && fullHandle == pendingFirstPageFullHandle) {
            return await pendingPage.value()
        }
        return try await base.listPreviews(
            displayName: displayName,
            specifier: specifier,
            supportedPlatforms: supportedPlatforms,
            page: page,
            pageSize: pageSize,
            distinctField: distinctField,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
    }
}

private actor PendingPage {
    private var continuation: CheckedContinuation<ServerPreviewsPage, Never>?
    private var requested: CheckedContinuation<Void, Never>?

    func value() async -> ServerPreviewsPage {
        await withCheckedContinuation {
            continuation = $0
            requested?.resume()
            requested = nil
        }
    }

    func waitUntilRequested() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { requested = $0 }
    }

    func resume(with page: ServerPreviewsPage) {
        continuation?.resume(returning: page)
        continuation = nil
    }
}
