import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistServer
import TuistSimulator

@testable import TuistPreviews

@Suite struct PreviewsViewModelTests {
    private let previewsService = MockListPreviewsServicing()
    private let projectsService = MockListProjectsServicing()
    private let tracksService = MockListPreviewTracksServicing()
    private let environmentService = MockServerEnvironmentServicing()
    private let appStorage = MockAppStoring()
    private let serverURL = URL(string: "https://self-hosted.example.com")!

    private func subject(
        previewsService: ListPreviewsServicing? = nil,
        tracksService: ListPreviewTracksServicing? = nil
    ) -> PreviewsViewModel {
        if tracksService == nil {
            given(self.tracksService).listPreviewTracks(fullHandle: .any, serverURL: .any)
                .willReturn(.init(totalCount: 0, tracks: []))
        }
        given(environmentService).url().willReturn(serverURL)
        given(appStorage)
            .set(.any as Parameter<SelectedProjectFullHandleKey.Type>, value: .any)
            .willReturn()
        return PreviewsViewModel(
            listProjectsService: projectsService,
            listPreviewsService: previewsService ?? self.previewsService,
            listPreviewTracksService: tracksService ?? self.tracksService,
            serverEnvironmentService: environmentService,
            appStorage: appStorage
        )
    }

    @Test func refreshing_an_empty_project_list_can_discover_projects_and_previews() async throws {
        let subject = subject()
        given(appStorage).get(.any as Parameter<SelectedProjectFullHandleKey.Type>).willReturn(nil)
        given(projectsService).listProjects(serverURL: .any).willReturn([])
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [.test(id: "new-preview")]))
        try await subject.onAppear()
        #expect(subject.projects.isEmpty)
        projectsService.reset([.given])
        given(projectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "team/app")])

        try await subject.refreshProjects()

        #expect(subject.selectedProject?.fullName == "team/app")
        #expect(subject.previews.map(\.id) == ["new-preview"])
    }

    @Test func track_filter_is_applied_to_every_page_and_reset_for_another_project() async throws {
        let subject = subject()
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .value(nil), supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .value(serverURL)
            )
            .willReturn(.test())
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .value("QA"), supportedPlatforms: .any,
                page: .value(1), pageSize: .value(20), distinctField: .any,
                fullHandle: .value("team/app"), serverURL: .value(serverURL)
            )
            .willReturn(.test(
                previews: [.test(id: "qa-1", track: "QA")],
                paginationMetadata: .test(hasNextPage: true, currentPage: 1)
            ))
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .value("QA"), supportedPlatforms: .any,
                page: .value(2), pageSize: .value(20), distinctField: .any,
                fullHandle: .value("team/app"), serverURL: .value(serverURL)
            )
            .willReturn(.test(
                previews: [.test(id: "qa-2", track: "QA")],
                paginationMetadata: .test(hasNextPage: false, currentPage: 2)
            ))

        try await subject.selectProject(.test(fullName: "team/app"))
        try await subject.selectTrack("QA")
        try await subject.loadMorePreviews()

        #expect(subject.previews.map(\.id) == ["qa-1", "qa-2"])
        #expect(!subject.hasMorePreviews)

        try await subject.selectProject(.test(fullName: "team/other"))
        #expect(subject.selectedTrack == nil)
    }

    @Test func track_filter_accepts_the_servers_case_insensitive_track_names() async throws {
        let subject = subject()
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [.test(track: "QA")]))
        try await subject.selectProject(.test())

        try await subject.selectTrack("qa")

        #expect(subject.previews.count == 1)
        #expect(subject.previews.first?.track == "QA")
    }

    @Test func reports_older_servers_that_ignore_the_track_filter() async throws {
        let subject = subject()
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [.test(track: "beta")]))
        try await subject.selectProject(.test())

        await #expect(throws: PreviewsViewModelError.trackFilteringUnsupported) {
            try await subject.selectTrack("QA")
        }
        #expect(subject.previews.isEmpty)
    }

    @Test(arguments: [nil, "team/other", "team/app", "team/deleted"] as [String?])
    func refreshing_projects_preserves_the_track_only_for_the_same_project(storedProject: String?) async throws {
        let subject = subject()
        given(appStorage)
            .get(.any as Parameter<SelectedProjectFullHandleKey.Type>)
            .willReturn(storedProject)
        given(projectsService).listProjects(serverURL: .value(serverURL))
            .willReturn([.test(fullName: "team/other"), .test(fullName: "team/app")])
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willProduce { _, _, track, _, _, _, _, fullHandle, _ in
                .test(previews: [.test(id: "\(fullHandle)-\(track ?? "all")", track: track)])
            }
        let initialProject = storedProject == "team/deleted" ? "team/deleted" : "team/app"
        try await subject.selectProject(.test(fullName: initialProject))
        try await subject.selectTrack("QA")

        try await subject.refreshProjects()

        let expectedProject = storedProject == "team/app" ? "team/app" : "team/other"
        let expectedTrack: String? = expectedProject == "team/app" ? "QA" : nil
        #expect(subject.selectedProject?.fullName == expectedProject)
        #expect(subject.selectedTrack == expectedTrack)
        #expect(subject.previews.map(\.id) == ["\(expectedProject)-\(expectedTrack ?? "all")"])
    }

    @Test(arguments: [1, 2], [false, true])
    func superseded_track_requests_ignore_results_and_errors(page: Int, fails: Bool) async throws {
        enum Failure: Error { case offline }
        let response = AsyncThrowingStream<ServerPreviewsPage, Error>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let subject = subject(previewsService: SuspendedPreviewsService(
            pendingPage: page, response: response.stream, didStart: started.continuation
        ))
        try await subject.selectProject(.test())
        if page == 2 { try await subject.selectTrack("QA") }
        let supersededRequest = Task {
            if page == 1 {
                try await subject.selectTrack("QA")
            } else {
                try await subject.loadMorePreviews()
            }
        }
        var startedIterator = started.stream.makeAsyncIterator()
        await startedIterator.next()
        try await subject.selectTrack("beta")

        if fails {
            response.continuation.finish(throwing: Failure.offline)
        } else {
            response.continuation.yield(.test(previews: [.test(id: "stale", track: "QA")]))
            response.continuation.finish()
        }
        try await supersededRequest.value

        #expect(subject.selectedTrack == "beta")
        #expect(subject.previews.map(\.id) == ["beta"])
        #expect(!subject.isLoadingPreviews)
        #expect(!subject.isLoadingMore)
    }

    @Test func track_choices_come_from_the_complete_server_list_and_survive_filtering() async throws {
        let subject = subject(tracksService: tracksService)
        given(tracksService).listPreviewTracks(fullHandle: .any, serverURL: .value(serverURL))
            .willReturn(.init(totalCount: 80, tracks: [
                .init(name: "beta", count: 2), .init(name: "nightly", count: 3), .init(name: "QA", count: 75),
            ]))
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [.test(track: "QA")]))
        try await subject.selectProject(.test())
        #expect(subject.availableTracks == ["beta", "nightly", "QA"])
        #expect(subject.totalPreviewCount == 80)
        #expect(subject.previewCount(for: "qa") == 75)

        try await subject.selectTrack("qa")
        #expect(subject.trackOptions == ["beta", "nightly", "qa"])
        #expect(subject.previews.count == 1)

        try await subject.selectTrack(nil)
        #expect(subject.selectedTrack == nil)
        #expect(subject.trackOptions == ["beta", "nightly", "QA"])
        verify(tracksService).listPreviewTracks(fullHandle: .any, serverURL: .any).called(.once)
    }

    @Test func switching_projects_replaces_track_choices() async throws {
        let subject = subject(tracksService: tracksService)
        given(tracksService).listPreviewTracks(fullHandle: .any, serverURL: .any)
            .willProduce { fullHandle, _ in
                .init(totalCount: 1, tracks: [.init(name: fullHandle == "team/app" ? "QA" : "beta", count: 1)])
            }
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: []))
        try await subject.selectProject(.test(fullName: "team/app"))
        try await subject.selectTrack("QA")

        try await subject.selectProject(.test(fullName: "team/other"))

        #expect(subject.selectedTrack == nil)
        #expect(subject.trackOptions == ["beta"])
    }

    @Test func older_servers_without_track_discovery_still_allow_browsing() async throws {
        let subject = subject(tracksService: tracksService)
        given(tracksService).listPreviewTracks(fullHandle: .any, serverURL: .any).willReturn(nil)
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [.test(id: "legacy", track: "QA")]))

        try await subject.selectProject(.test())

        #expect(subject.previews.map(\.id) == ["legacy"])
        #expect(subject.availableTracks.isEmpty)
        #expect(!subject.isTrackSelectionSupported)
        #expect(!subject.isLoadingPreviews)
    }

    @Test(arguments: [false, true])
    func superseded_track_discovery_does_not_change_another_projects_choices(fails: Bool) async throws {
        enum Failure: Error { case offline }
        let response = AsyncThrowingStream<[String]?, Error>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let subject = subject(tracksService: SuspendedTracksService(response: response.stream, didStart: started.continuation))
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: []))
        let stale = Task { try await subject.selectProject(.test(fullName: "team/app")) }
        var startedIterator = started.stream.makeAsyncIterator()
        await startedIterator.next()
        try await subject.selectProject(.test(fullName: "team/other"))
        if fails {
            response.continuation.finish(throwing: Failure.offline)
        } else {
            response.continuation.yield(["stale-track"])
            response.continuation.finish()
        }
        try await stale.value

        #expect(subject.selectedProject?.fullName == "team/other")
        #expect(subject.trackOptions == ["beta"])
        #expect(!subject.isLoadingPreviews)
    }

    @Test func search_combines_with_tracks_across_pages_without_changing_project_counts() async throws {
        let subject = subject(tracksService: tracksService)
        given(tracksService).listPreviewTracks(fullHandle: .any, serverURL: .any)
            .willReturn(.init(totalCount: 6, tracks: [.init(name: "beta", count: 2), .init(name: "QA", count: 4)]))
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: []))
        given(previewsService)
            .searchPreviews(
                search: .value("BLUE"),
                track: .any,
                page: .any,
                pageSize: .value(20),
                fullHandle: .any,
                serverURL: .any
            )
            .willProduce { _, track, page, _, _, _ in
                .test(
                    previews: [.test(id: "page-\(page)", displayName: "Blueprint App", track: track)],
                    paginationMetadata: .test(hasNextPage: page == 1, currentPage: page)
                )
            }
        try await subject.selectProject(.test())
        try await subject.selectTrack("QA")
        try await subject.searchPreviews("  BLUE  ")
        try await subject.loadMorePreviews()
        #expect(subject.previews.map(\.id) == ["page-1", "page-2"])
        #expect(subject.searchQuery == "BLUE")
        #expect(subject.totalPreviewCount == 6)
        #expect(subject.previewCount(for: "QA") == 4)
        try await subject.refreshPreviews()
        #expect(subject.previews.map(\.id) == ["page-1"])
        #expect(subject.searchQuery == "BLUE")
        #expect(subject.selectedTrack == "QA")
        #expect(subject.totalPreviewCount == 6)
        try await subject.selectTrack("beta")
        #expect(subject.previews.map(\.id) == ["page-1"])
        #expect(subject.previews.first?.track == "beta")
        try await subject.selectProject(.test(fullName: "team/other"))
        #expect(subject.searchQuery.isEmpty)
        #expect(subject.selectedTrack == nil)
    }

    @Test func search_accepts_matches_in_full_release_notes() async throws {
        let subject = subject()
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: []))
        given(previewsService)
            .searchPreviews(
                search: .value("checkout"),
                track: .any,
                page: .any,
                pageSize: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(.test(previews: [.test(displayName: "Atlas", releaseNotes: "Build 204\nFix CHECKOUT")]))
        try await subject.selectProject(.test())
        try await subject.searchPreviews("checkout")
        #expect(subject.previews.first?.displayName == "Atlas")
        #expect(subject.previews.first?.releaseNotesSummary == "Build 204")
    }

    @Test func reports_older_servers_that_ignore_search() async throws {
        let subject = subject()
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: []))
        given(previewsService)
            .searchPreviews(search: .any, track: .any, page: .any, pageSize: .any, fullHandle: .any, serverURL: .any)
            .willReturn(.test(previews: [.test(displayName: "Other App")]))
        try await subject.selectProject(.test())
        await #expect(throws: PreviewsViewModelError.searchUnsupported) {
            try await subject.searchPreviews("Blueprint")
        }
        #expect(subject.previews.isEmpty)
    }

    @Test(arguments: [false, true])
    func superseded_search_results_and_errors_are_ignored(fails: Bool) async throws {
        enum Failure: Error { case offline }
        let response = AsyncThrowingStream<ServerPreviewsPage, Error>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let subject = subject(previewsService: SuspendedSearchService(response: response.stream, didStart: started.continuation))
        try await subject.selectProject(.test())
        let stale = Task { try await subject.searchPreviews("old") }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        try await subject.searchPreviews("new")
        if fails {
            response.continuation.finish(throwing: Failure.offline)
        } else {
            response.continuation.yield(.test(previews: [.test(displayName: "old result")]))
            response.continuation.finish()
        }
        try await stale.value
        #expect(subject.previews.first?.displayName == "new result")
        #expect(subject.searchQuery == "new")
        #expect(!subject.isLoadingPreviews)
    }

    @Test func failed_pagination_can_be_retried() async throws {
        enum Failure: Error, Equatable { case offline }
        let subject = subject()
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .value(1), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(paginationMetadata: .test(hasNextPage: true, currentPage: 1)))
        given(previewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .value(2), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willThrow(Failure.offline)

        try await subject.selectProject(.test())
        await #expect(throws: Failure.offline) { try await subject.loadMorePreviews() }
        #expect(!subject.isLoadingMore)
        #expect(subject.hasMorePreviews)
    }
}

private struct SuspendedSearchService: ListPreviewsServicing {
    let response: AsyncThrowingStream<ServerPreviewsPage, Error>
    let didStart: AsyncStream<Void>.Continuation

    func listPreviews(
        displayName _: String?, specifier _: String?, track _: String?, supportedPlatforms _: [DestinationType],
        page _: Int?, pageSize _: Int?, distinctField _: ListPreviewsDistinctField?, fullHandle _: String, serverURL _: URL
    ) async throws -> ServerPreviewsPage {
        .test(previews: [])
    }

    func searchPreviews(
        search: String, track _: String?, page _: Int, pageSize _: Int, fullHandle _: String, serverURL _: URL
    ) async throws -> ServerPreviewsPage {
        guard search == "old" else { return .test(previews: [.test(displayName: "new result")]) }
        didStart.yield()
        for try await page in response {
            return page
        }
        throw CancellationError()
    }
}

private struct SuspendedTracksService: ListPreviewTracksServicing {
    let response: AsyncThrowingStream<[String]?, Error>
    let didStart: AsyncStream<Void>.Continuation

    func listPreviewTracks(fullHandle: String, serverURL _: URL) async throws -> ServerPreviewTrackSummary? {
        guard fullHandle == "team/app" else {
            return .init(totalCount: 1, tracks: [.init(name: "beta", count: 1)])
        }
        didStart.yield()
        for try await tracks in response {
            return tracks.map { names in
                .init(totalCount: names.count, tracks: names.map { .init(name: $0, count: 1) })
            }
        }
        throw CancellationError()
    }
}

private struct SuspendedPreviewsService: ListPreviewsServicing {
    func searchPreviews(
        search _: String, track _: String?, page _: Int, pageSize _: Int, fullHandle _: String, serverURL _: URL
    ) async throws -> ServerPreviewsPage {
        throw CancellationError()
    }

    let pendingPage: Int
    let response: AsyncThrowingStream<ServerPreviewsPage, Error>
    let didStart: AsyncStream<Void>.Continuation

    func listPreviews(
        displayName _: String?, specifier _: String?, track: String?, supportedPlatforms _: [DestinationType],
        page: Int?, pageSize _: Int?, distinctField _: ListPreviewsDistinctField?, fullHandle _: String, serverURL _: URL
    ) async throws -> ServerPreviewsPage {
        guard track == "QA", page == pendingPage else {
            return .test(
                previews: [.test(id: track ?? "all", track: track)],
                paginationMetadata: .test(hasNextPage: true, currentPage: page ?? 1)
            )
        }
        didStart.yield()
        for try await previewsPage in response {
            return previewsPage
        }
        throw CancellationError()
    }
}
