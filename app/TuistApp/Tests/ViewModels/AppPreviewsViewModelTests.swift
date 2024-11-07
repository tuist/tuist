import Foundation
import Mockable
import TuistServer
import TuistSupportTesting
import XCTest

@testable import Tuist

final class AppPreviewsViewModelTests: TuistUnitTestCase {
    private var subject: AppPreviewsViewModel!
    private var deviceService: MockDeviceServicing!
    private var appStorage: MockAppStoring!
    private var listPreviewsService: MockListPreviewsServicing!
    private var listProjectsService: MockListProjectsServicing!
    private var serverURLService: Tuist.MockServerURLServicing!

    override func setUp() {
        super.setUp()

        deviceService = MockDeviceServicing()
        listPreviewsService = MockListPreviewsServicing()
        listProjectsService = MockListProjectsServicing()
        serverURLService = MockServerURLServicing()
        appStorage = MockAppStoring()
        subject = AppPreviewsViewModel(
            deviceService: deviceService,
            listProjectsService: listProjectsService,
            listPreviewsService: listPreviewsService,
            serverURLService: serverURLService,
            appStorage: appStorage
        )

        given(serverURLService)
            .serverURL()
            .willReturn(.test())
    }

    override func tearDown() {
        deviceService = nil
        listPreviewsService = nil
        listProjectsService = nil
        serverURLService = nil
        appStorage = nil
        subject = nil

        super.tearDown()
    }

    func test_load_app_previews_from_cache() {
        // Given
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn([.test()])

        // When
        subject.loadAppPreviewsFromCache()

        // Then
        XCTAssertEqual(subject.appPreviews, [.test()])
    }

    func test_on_appear_updates_app_previews() async throws {
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

        // When
        try await subject.onAppear()

        // Then
        XCTAssertEqual(
            subject.appPreviews,
            [
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

    func test_launch_preview_when_no_preview_found() async throws {
        // Given
        let appPreview: Tuist.AppPreview = .test()
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn([appPreview])

        subject.loadAppPreviewsFromCache()

        given(listPreviewsService)
            .listPreviews(
                displayName: .any,
                specifier: .any,
                page: .any,
                pageSize: .any,
                distinctField: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn([])

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.launchAppPreview(appPreview),
            AppPreviewsModelError.previewNotFound(appPreview.displayName)
        )
    }

    func test_launch_preview() async throws {
        // Given
        let appPreview: Tuist.AppPreview = .test()
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn([appPreview])

        subject.loadAppPreviewsFromCache()

        given(listPreviewsService)
            .listPreviews(
                displayName: .any,
                specifier: .any,
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
    }
}
