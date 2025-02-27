import Foundation
import Mockable
import Testing
import class TuistApp.MockServerURLServicing
import TuistServer
import TuistSupportTesting

@testable import TuistApp

@Suite struct AppPreviewsViewModelTests {
    private let subject: AppPreviewsViewModel
    private let appCredentialsService: MockAppCredentialsServicing
    private let deviceService: MockDeviceServicing
    private let appStorage: MockAppStoring
    private let listPreviewsService: MockListPreviewsServicing
    private let listProjectsService: MockListProjectsServicing
    private let serverURLService: MockServerURLServicing

    init() {
        appCredentialsService = MockAppCredentialsServicing()
        deviceService = MockDeviceServicing()
        listPreviewsService = MockListPreviewsServicing()
        listProjectsService = MockListProjectsServicing()
        serverURLService = MockServerURLServicing()
        appStorage = MockAppStoring()
        subject = AppPreviewsViewModel(
            appCredentialsService: appCredentialsService,
            deviceService: deviceService,
            listProjectsService: listProjectsService,
            listPreviewsService: listPreviewsService,
            serverURLService: serverURLService,
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

        given(serverURLService)
            .serverURL()
            .willReturn(.test())
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

    @Test func on_appear_updates_app_previews_when_logged_in() async throws {
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
                specifier: .any,
                supportedPlatforms: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .any
            )
            .willReturn(
                [
                    .test(
                        displayName: "App_B"
                    ),
                    .test(
                        displayName: "App_A"
                    ),
                ]
            )

        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        given(appCredentialsService)
            .authenticationState
            .willReturn(.loggedIn(accountHandle: "tuistrocks"))

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

        verify(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .called(1)
    }

    @Test func update_app_previews_is_skipped_when_logged_out() async throws {
        // Given
        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        given(appCredentialsService)
            .authenticationState
            .willReturn(.loggedOut)

        // When
        try await subject.onAppear()

        // Then
        verify(listProjectsService)
            .listProjects(serverURL: .any)
            .called(0)
        #expect(subject.appPreviews == [])
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
                specifier: .any,
                supportedPlatforms: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn([])

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
                specifier: .any,
                supportedPlatforms: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(
                [
                    .test(id: "preview-id"),
                ]
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
                specifier: .any,
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
