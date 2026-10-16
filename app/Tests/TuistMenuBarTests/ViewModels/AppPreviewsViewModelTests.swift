import Foundation
import Mockable
import Testing
import TuistAppStorage
import TuistAuthentication
import TuistServer
import TuistTesting

@testable import TuistMenuBar

@Suite struct AppPreviewsViewModelTests {
    private let subject: AppPreviewsViewModel
    private let deviceService: MockDeviceServicing
    private let appStorage: MockAppStoring
    private let listPreviewsService: MockListPreviewsServicing
    private let listProjectsService: MockListProjectsServicing
    private let serverEnvironmentService: MockServerEnvironmentServicing

    init() {
        appStorage = MockAppStoring()
        deviceService = MockDeviceServicing()
        listPreviewsService = MockListPreviewsServicing()
        listProjectsService = MockListProjectsServicing()
        serverEnvironmentService = MockServerEnvironmentServicing()

        subject = AppPreviewsViewModel(
            deviceService: deviceService,
            listProjectsService: listProjectsService,
            listPreviewsService: listPreviewsService,
            serverEnvironmentService: serverEnvironmentService,
            appStorage: appStorage
        )

        given(deviceService)
            .selectedDevice
            .willReturn(
                .device(
                    .test(
                        platform: .iOS
                    )
                )
            )

        given(serverEnvironmentService)
            .url()
            .willReturn(.test())

        given(appStorage)
            .get(.any as Parameter<AppPreviewsServerURLKey.Type>)
            .willReturn(nil)

        given(appStorage)
            .set(.any as Parameter<AppPreviewsServerURLKey.Type>, value: .any)
            .willReturn()
    }

    @Test func does_not_load_app_previews_cached_for_another_server() {
        // Given
        let appStorage = MockAppStoring()
        let subject = AppPreviewsViewModel(
            deviceService: deviceService,
            listProjectsService: listProjectsService,
            listPreviewsService: listPreviewsService,
            serverEnvironmentService: serverEnvironmentService,
            appStorage: appStorage
        )
        given(appStorage)
            .get(.any as Parameter<AppPreviewsServerURLKey.Type>)
            .willReturn("https://other.example.com")

        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn([.test()])

        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        given(appStorage)
            .set(.any as Parameter<AppPreviewsServerURLKey.Type>, value: .any)
            .willReturn()

        // When
        subject.loadAppPreviewsFromCache()

        // Then
        #expect(subject.appPreviews == [])
    }

    @Test func load_app_previews_from_cache() {
        // Given
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn([.test()])

        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        // When
        subject.loadAppPreviewsFromCache()

        // Then
        #expect(subject.appPreviews == [.test()])
    }

    @Test func on_appear_updates_app_previews() async throws {
        // Given
        given(listProjectsService)
            .listProjects(serverURL: .any)
            .willReturn(
                [
                    .test(
                        fullName: "tuist/tuist"
                    ),
                ]
            )

        given(listPreviewsService)
            .listPreviews(
                displayName: .any,
                specifier: .value(nil),
                track: .value(nil),
                supportedPlatforms: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .any
            )
            .willReturn(
                .test(
                    previews: [
                        .test(
                            displayName: "App_B"
                        ),
                        .test(
                            displayName: "App_A"
                        ),
                    ],
                    paginationMetadata: .test(hasNextPage: false)
                )
            )

        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        // When
        try await subject.onAppear()

        // Then
        #expect(
            subject.appPreviews == [
                .test(
                    displayName: "App_A"
                ),
                .test(
                    displayName: "App_B"
                ),
            ]
        )

        // Mockable matches generic `set` calls across key types, so this counts the previews and their server.
        verify(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .called(2)
    }

    @Test func lists_previews_from_all_branches_and_pages() async throws {
        given(appStorage).set(.any as Parameter<AppPreviewsKey.Type>, value: .any).willReturn()
        given(listProjectsService).listProjects(serverURL: .any).willReturn([.test(fullName: "team/app")])
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .value(nil), track: .value(nil), supportedPlatforms: .any,
                page: .value(1), pageSize: .value(20), distinctField: .any,
                fullHandle: .value("team/app"), serverURL: .any
            )
            .willReturn(.test(
                previews: [.test(id: "preview-a", bundleIdentifier: "dev.app.a", displayName: "A", gitBranch: "feature/qa")],
                paginationMetadata: .test(hasNextPage: true, currentPage: 1)
            ))
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .value(nil), track: .value(nil), supportedPlatforms: .any,
                page: .value(2), pageSize: .value(20), distinctField: .any,
                fullHandle: .value("team/app"), serverURL: .any
            )
            .willReturn(.test(
                previews: [.test(id: "preview-b", bundleIdentifier: "dev.app.b", displayName: "B")],
                paginationMetadata: .test(hasNextPage: false, currentPage: 2)
            ))

        try await subject.onAppear()

        #expect(subject.appPreviews.map(\.displayName) == ["A", "B"])
    }

    @Test func launches_the_selected_bundle_even_when_another_app_is_newer() async throws {
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .value(nil), track: .value(nil), supportedPlatforms: .any,
                page: .value(1), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(
                previews: [.test(id: "other-preview", bundleIdentifier: "dev.other")],
                paginationMetadata: .test(hasNextPage: true, currentPage: 1)
            ))
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .value(nil), track: .value(nil), supportedPlatforms: .any,
                page: .value(2), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(
                previews: [.test(id: "selected-preview", bundleIdentifier: "dev.tuist.app")],
                paginationMetadata: .test(hasNextPage: false, currentPage: 2)
            ))
        given(deviceService).launchPreview(with: .any, fullHandle: .any, serverURL: .any).willReturn()

        try await subject.launchAppPreview(.test(bundleIdentifier: "dev.tuist.app"))

        verify(deviceService)
            .launchPreview(with: .value("selected-preview"), fullHandle: .any, serverURL: .any)
            .called(1)
    }

    @Test func falls_back_for_older_servers_that_choose_distinct_before_platforms() async throws {
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .value(.bundleIdentifier), fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [], paginationMetadata: .test(hasNextPage: false)))
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .value(nil), fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [.test(id: "compatible-build")], paginationMetadata: .test(hasNextPage: false)))
        given(deviceService).launchPreview(with: .any, fullHandle: .any, serverURL: .any).willReturn()

        try await subject.launchAppPreview(.test())

        verify(deviceService).launchPreview(with: .value("compatible-build"), fullHandle: .any, serverURL: .any).called(1)
    }

    @Test func rejects_servers_that_repeat_pages() async throws {
        given(listPreviewsService)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .any, pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(previews: [.test(bundleIdentifier: "other.app")], paginationMetadata: .test(hasNextPage: true)))

        await #expect(throws: AppPreviewsModelError.paginationDidNotAdvance) {
            try await subject.launchAppPreview(.test())
        }
    }

    @Test func launch_preview_when_no_preview_found() async throws {
        // Given
        let appPreview: AppPreview = .test()
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn([appPreview])

        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        subject.loadAppPreviewsFromCache()

        given(listPreviewsService)
            .listPreviews(
                displayName: .any,
                specifier: .value(nil),
                track: .value(nil),
                supportedPlatforms: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(.test(previews: [], paginationMetadata: .test(hasNextPage: false)))

        // When / Then
        await #expect(throws: AppPreviewsModelError.previewNotFound(appPreview.displayName)) {
            try await subject.launchAppPreview(appPreview)
        }
    }

    @Test func launch_preview() async throws {
        // Given
        let appPreview: AppPreview = .test()
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn([appPreview])

        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        subject.loadAppPreviewsFromCache()

        given(listPreviewsService)
            .listPreviews(
                displayName: .any,
                specifier: .value(nil),
                track: .value(nil),
                supportedPlatforms: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(
                .test(
                    previews: [
                        .test(id: "preview-id"),
                    ]
                )
            )

        given(deviceService)
            .launchPreview(
                with: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn()

        // When / Then
        try await subject.launchAppPreview(appPreview)

        // Then
        verify(deviceService)
            .launchPreview(
                with: .value("preview-id"),
                fullHandle: .any,
                serverURL: .any
            )
            .called(1)

        verify(listPreviewsService)
            .listPreviews(
                displayName: .any,
                specifier: .value(nil),
                track: .value(nil),
                supportedPlatforms: .value([.device(.iOS)]),
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .called(1)
    }
}
