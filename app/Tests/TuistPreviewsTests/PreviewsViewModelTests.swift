import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistServer

@testable import TuistPreviews

@Suite struct PreviewsViewModelTests {
    private let previewsService = MockListPreviewsServicing()
    private let projectsService = MockListProjectsServicing()
    private let environmentService = MockServerEnvironmentServicing()
    private let appStorage = MockAppStoring()
    private let serverURL = URL(string: "https://self-hosted.example.com")!

    private func subject() -> PreviewsViewModel {
        given(environmentService).url().willReturn(serverURL)
        given(appStorage)
            .set(.any as Parameter<SelectedProjectFullHandleKey.Type>, value: .any)
            .willReturn()
        return PreviewsViewModel(
            listProjectsService: projectsService,
            listPreviewsService: previewsService,
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
