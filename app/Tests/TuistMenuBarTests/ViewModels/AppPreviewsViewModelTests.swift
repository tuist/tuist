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
                specifier: .any,
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
                    ]
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

        verify(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .called(1)
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
            .willReturn(.test(previews: []))

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
