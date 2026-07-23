import Foundation
import Mockable
import Synchronization
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
        let appStorage = MockAppStoring()
        let deviceService = MockDeviceServicing()
        let listPreviewsService = MockListPreviewsServicing()
        let listProjectsService = MockListProjectsServicing()
        let serverEnvironmentService = MockServerEnvironmentServicing()
        self.appStorage = appStorage
        self.deviceService = deviceService
        self.listPreviewsService = listPreviewsService
        self.listProjectsService = listProjectsService
        self.serverEnvironmentService = serverEnvironmentService

        given(serverEnvironmentService)
            .url()
            .willReturn(.test())

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
    }

    @Test func load_app_previews_from_cache() {
        // Given
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn(AppPreviewsCache(serverURL: .test(), appPreviews: [.test()]))

        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        // When
        subject.loadAppPreviewsFromCache()

        // Then
        #expect(subject.appPreviews == [.test()])
    }

    @Test func load_app_previews_from_cache_ignores_another_server() {
        let otherServerPreview: AppPreview = .test(displayName: "Other server")
        given(appStorage)
            .get(.any as Parameter<AppPreviewsKey.Type>)
            .willReturn(
                AppPreviewsCache(
                    serverURL: URL(string: "https://other.tuist.dev")!,
                    appPreviews: [otherServerPreview]
                )
            )
        given(appStorage)
            .set(.any as Parameter<AppPreviewsKey.Type>, value: .any)
            .willReturn()

        subject.loadAppPreviewsFromCache()

        #expect(subject.appPreviews.isEmpty)
    }

    @Test func load_app_previews_from_cache_migrates_legacy_previews() {
        let legacyPreview: AppPreview = .test(displayName: "Legacy")
        let appStorage = LegacyAppPreviewsStorage(appPreviews: [legacyPreview])
        let serverEnvironmentService = AppServerEnvironmentService(
            appStorage: appStorage,
            defaultServerEnvironmentService: TestServerEnvironmentService(serverURL: .test())
        )
        let subject = AppPreviewsViewModel(
            deviceService: deviceService,
            listProjectsService: listProjectsService,
            listPreviewsService: listPreviewsService,
            serverEnvironmentService: serverEnvironmentService,
            appStorage: appStorage
        )

        subject.loadAppPreviewsFromCache()

        #expect(subject.appPreviews == [legacyPreview])
        #expect(appStorage.cache == AppPreviewsCache(serverURL: .test(), appPreviews: [legacyPreview]))
    }

    @Test func load_app_previews_from_cache_discards_legacy_previews_for_a_custom_server() {
        let customServerURL = URL(string: "https://custom.tuist.dev")!
        let legacyPreview: AppPreview = .test(displayName: "Legacy")
        let appStorage = LegacyAppPreviewsStorage(
            appPreviews: [legacyPreview],
            serverURLString: customServerURL.absoluteString
        )
        let serverEnvironmentService = AppServerEnvironmentService(
            appStorage: appStorage,
            defaultServerEnvironmentService: TestServerEnvironmentService(serverURL: .test())
        )
        let subject = AppPreviewsViewModel(
            deviceService: deviceService,
            listProjectsService: listProjectsService,
            listPreviewsService: listPreviewsService,
            serverEnvironmentService: serverEnvironmentService,
            appStorage: appStorage
        )

        subject.loadAppPreviewsFromCache()

        #expect(subject.appPreviews.isEmpty)
        #expect(appStorage.cache == AppPreviewsCache(serverURL: customServerURL, appPreviews: []))
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
            .willReturn(AppPreviewsCache(serverURL: .test(), appPreviews: [appPreview]))

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
            .willReturn(AppPreviewsCache(serverURL: .test(), appPreviews: [appPreview]))

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

private final class LegacyAppPreviewsStorage: AppStoring {
    private struct State {
        var cache: AppPreviewsCache?
        let appPreviews: [AppPreview]
        let serverURLString: String?
    }

    private let state: Mutex<State>

    init(
        appPreviews: [AppPreview],
        serverURLString: String? = nil
    ) {
        state = Mutex(State(cache: nil, appPreviews: appPreviews, serverURLString: serverURLString))
    }

    var cache: AppPreviewsCache? {
        return state.withLock(\.cache)
    }

    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        if ObjectIdentifier(key) == ObjectIdentifier(AppPreviewsKey.self) {
            throw LegacyAppPreviewsStorageError.legacyValue
        }
        if ObjectIdentifier(key) == ObjectIdentifier(LegacyAppPreviewsKey.self) {
            return state.withLock(\.appPreviews) as! Key.Value
        }
        if ObjectIdentifier(key) == ObjectIdentifier(AppServerURLKey.self) {
            return state.withLock(\.serverURLString) as! Key.Value
        }
        return key.defaultValue
    }

    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        guard ObjectIdentifier(key) == ObjectIdentifier(AppPreviewsKey.self),
              let cache = value as? AppPreviewsCache
        else {
            return
        }
        state.withLock { $0.cache = cache }
    }
}

private enum LegacyAppPreviewsStorageError: Error {
    case legacyValue
}

private struct TestServerEnvironmentService: ServerEnvironmentServicing {
    let serverURL: URL

    func url() -> URL {
        return serverURL
    }

    func oauthClientId() -> String {
        return "test-client-id"
    }

    func url(configServerURL _: URL) throws -> URL {
        return serverURL
    }
}
