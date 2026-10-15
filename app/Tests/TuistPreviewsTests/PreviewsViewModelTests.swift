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
    private let environmentService = MockServerEnvironmentServicing()
    private let appStorage = MockAppStoring()
    private let serverURL = URL(string: "https://self-hosted.example.com")!

    private func subject(previewsService: ListPreviewsServicing? = nil) -> PreviewsViewModel {
        given(environmentService).url().willReturn(serverURL)
        given(appStorage)
            .set(.any as Parameter<SelectedProjectFullHandleKey.Type>, value: .any)
            .willReturn()
        return PreviewsViewModel(
            listProjectsService: projectsService,
            listPreviewsService: previewsService ?? self.previewsService,
            serverEnvironmentService: environmentService,
            appStorage: appStorage
        )
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

private struct SuspendedPreviewsService: ListPreviewsServicing {
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
