import Foundation
import MockableTest
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting
import XcodeGraph

@testable import TuistKit

final class ShareServiceTests: TuistUnitTestCase {
    private var subject: ShareService!
    private var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocating!
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var previewsUploadService: MockPreviewsUploadServicing!
    private var configLoader: MockConfigLoading!
    private var serverURLService: MockServerURLServicing!
    private var manifestLoader: MockManifestLoading!
    private var manifestGraphLoader: MockManifestGraphLoading!
    private var userInputReader: MockUserInputReading!
    private var defaultConfigurationFetcher: MockDefaultConfigurationFetching!
    private var appBundleLoader: MockAppBundleLoading!

    override func setUp() {
        super.setUp()

        xcodeProjectBuildDirectoryLocator = .init()
        buildGraphInspector = .init()
        previewsUploadService = .init()
        configLoader = .init()
        serverURLService = .init()
        manifestLoader = .init()
        manifestGraphLoader = .init()
        userInputReader = .init()
        defaultConfigurationFetcher = .init()
        appBundleLoader = .init()
        subject = ShareService(
            fileHandler: fileHandler,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            buildGraphInspector: buildGraphInspector,
            previewsUploadService: previewsUploadService,
            configLoader: configLoader,
            serverURLService: serverURLService,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            userInputReader: userInputReader,
            defaultConfigurationFetcher: defaultConfigurationFetcher,
            appBundleLoader: appBundleLoader
        )

        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        Matcher.register([GraphTarget].self)
    }

    override func tearDown() {
        xcodeProjectBuildDirectoryLocator = nil
        buildGraphInspector = nil
        previewsUploadService = nil
        configLoader = nil
        serverURLService = nil
        manifestLoader = nil
        manifestGraphLoader = nil
        userInputReader = nil
        defaultConfigurationFetcher = nil
        subject = nil

        Matcher.reset()

        super.tearDown()
    }

    func test_share_tuist_project_when_multiple_apps_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: ["AppOne", "AppTwo"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil
            ),
            ShareServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        )
    }

    func test_share_tuist_project() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        let projectPath = try temporaryPath()
        let appTarget: Target = .test(
            name: "AppTarget",
            destinations: [.appleVision, .iPhone],
            productName: "App"
        )
        let appTargetTwo: Target = .test(name: "AppTwo")
        let project: Project = .test(
            targets: [
                appTarget,
                appTargetTwo,
            ]
        )
        let graphAppTarget = GraphTarget(path: projectPath, target: appTarget, project: project)
        let graphAppTargetTwo = GraphTarget(path: projectPath, target: appTargetTwo, project: project)

        given(manifestGraphLoader)
            .load(path: .any)
            .willReturn(
                (
                    .test(
                        projects: [
                            projectPath: project,
                        ]
                    ),
                    [],
                    MapperEnvironment(),
                    []
                )
            )

        given(userInputReader)
            .readValue(
                asking: .any,
                values: .value([
                    graphAppTarget,
                    graphAppTargetTwo,
                ]),
                valueDescription: .any
            )
            .willReturn(graphAppTarget)

        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, config: .any, graph: .any)
            .willReturn("Debug")

        let iosPath = try temporaryPath()
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .value(.iOS),
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(iosPath)
        try fileHandler.touch(iosPath.appending(component: "App.app"))

        let visionOSPath = try temporaryPath()
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .value(.visionOS),
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(visionOSPath)
        try fileHandler.touch(visionOSPath.appending(component: "App.app"))

        let shareURL: URL = .test()
        given(previewsUploadService)
            .uploadPreviews(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(shareURL)

        // When
        try await subject.run(
            path: nil,
            apps: [],
            configuration: nil,
            platforms: [],
            derivedDataPath: nil
        )

        // Then
        verify(previewsUploadService)
            .uploadPreviews(
                .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production)
            )
            .called(1)

        XCTAssertStandardOutput(
            pattern: "App uploaded – share it with others using the following link: \(shareURL.absoluteString)"
        )
    }

    func test_share_tuist_project_with_a_specified_app() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        let projectPath = try temporaryPath()
        let appTarget: Target = .test(
            name: "App",
            destinations: [.appleVision, .iPhone]
        )
        let appTargetTwo: Target = .test(name: "AppTwo")
        let project: Project = .test(
            targets: [
                appTarget,
                appTargetTwo,
            ]
        )
        let graphAppTargetTwo = GraphTarget(path: projectPath, target: appTargetTwo, project: project)

        given(manifestGraphLoader)
            .load(path: .any)
            .willReturn(
                (
                    .test(
                        projects: [
                            projectPath: project,
                        ]
                    ),
                    [],
                    MapperEnvironment(),
                    []
                )
            )

        given(userInputReader)
            .readValue(
                asking: .any,
                values: .value([
                    graphAppTargetTwo,
                ]),
                valueDescription: .any
            )
            .willReturn(graphAppTargetTwo)

        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, config: .any, graph: .any)
            .willReturn("Debug")

        let iosPath = try temporaryPath()
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .value(.iOS),
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(iosPath)
        try fileHandler.touch(iosPath.appending(component: "AppTwo.app"))

        let shareURL: URL = .test()
        given(previewsUploadService)
            .uploadPreviews(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(shareURL)

        // When
        try await subject.run(
            path: nil,
            apps: ["AppTwo"],
            configuration: nil,
            platforms: [],
            derivedDataPath: nil
        )

        // Then
        verify(previewsUploadService)
            .uploadPreviews(
                .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production)
            )
            .called(1)

        XCTAssertStandardOutput(
            pattern: "AppTwo uploaded – share it with others using the following link: \(shareURL.absoluteString)"
        )
    }

    func test_share_xcode_app_when_no_app_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: [],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil
            ),
            ShareServiceError.appNotSpecified
        )
    }

    func test_share_xcode_app_when_multiple_apps_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: ["AppOne", "AppTwo"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil
            ),
            ShareServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        )
    }

    func test_share_xcode_app_when_no_platforms_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: ["App"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil
            ),
            ShareServiceError.platformsNotSpecified
        )
    }

    func test_share_xcode_app_when_no_project_or_workspace_not_found() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        let path = try temporaryPath()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: path.pathString,
                apps: ["App"],
                configuration: nil,
                platforms: [.iOS],
                derivedDataPath: nil
            ),
            ShareServiceError.projectOrWorkspaceNotFound(path: path.pathString)
        )
    }

    func test_share_xcode_app() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        let path = try temporaryPath()
        let xcodeprojPath = try temporaryPath().appending(component: "App.xcodeproj")
        try fileHandler.touch(xcodeprojPath)

        let iosPath = try temporaryPath()
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                platform: .value(.iOS),
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(iosPath)
        try fileHandler.touch(iosPath.appending(component: "App.app"))

        let shareURL: URL = .test()
        given(previewsUploadService)
            .uploadPreviews(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(shareURL)

        // When
        try await subject.run(
            path: path.pathString,
            apps: ["App"],
            configuration: nil,
            platforms: [.iOS],
            derivedDataPath: nil
        )

        // Then
        verify(previewsUploadService)
            .uploadPreviews(
                .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production)
            )
            .called(1)

        XCTAssertStandardOutput(
            pattern: "App uploaded – share it with others using the following link: \(shareURL.absoluteString)"
        )
    }

    func test_share_different_apps() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let appOne = try temporaryPath().appending(component: "AppOne.app")
        let appTwo = try temporaryPath().appending(component: "AppTwo.app")

        given(appBundleLoader)
            .load(.value(appOne))
            .willReturn(.test(infoPlist: .test(name: "AppOne")))

        given(appBundleLoader)
            .load(.value(appTwo))
            .willReturn(.test(infoPlist: .test(name: "AppTwo")))

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: [
                    appOne.pathString,
                    appTwo.pathString,
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil
            ),
            ShareServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        )
    }

    func test_share_apps() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let iosApp = try temporaryPath().appending(components: "iOS", "App.app")
        let visionOSApp = try temporaryPath().appending(components: "visionOs", "App.app")

        given(appBundleLoader)
            .load(.value(iosApp))
            .willReturn(.test(infoPlist: .test(name: "App")))

        given(appBundleLoader)
            .load(.value(visionOSApp))
            .willReturn(.test(infoPlist: .test(name: "App")))

        let shareURL: URL = .test()
        given(previewsUploadService)
            .uploadPreviews(
                .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(shareURL)

        // When
        try await subject.run(
            path: nil,
            apps: [
                iosApp.pathString,
                visionOSApp.pathString,
            ],
            configuration: nil,
            platforms: [],
            derivedDataPath: nil
        )

        // Then
        verify(previewsUploadService)
            .uploadPreviews(
                .value([iosApp, visionOSApp]),
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production)
            )
            .called(1)

        XCTAssertStandardOutput(
            pattern: "App uploaded – share it with others using the following link: \(shareURL.absoluteString)"
        )
    }
}
