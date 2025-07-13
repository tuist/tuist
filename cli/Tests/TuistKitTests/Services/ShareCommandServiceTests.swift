import Foundation
import Mockable
import SnapshotTesting
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

final class ShareCommandServiceTests: TuistUnitTestCase {
    private var subject: ShareCommandService!
    private var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocating!
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var previewsUploadService: MockPreviewsUploadServicing!
    private var configLoader: MockConfigLoading!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var manifestLoader: MockManifestLoading!
    private var manifestGraphLoader: MockManifestGraphLoading!
    private var userInputReader: MockUserInputReading!
    private var defaultConfigurationFetcher: MockDefaultConfigurationFetching!
    private var appBundleLoader: MockAppBundleLoading!
    private var fileUnarchiver: MockFileUnarchiving!
    private let shareURL: URL = .test()

    override func setUp() {
        super.setUp()

        xcodeProjectBuildDirectoryLocator = .init()
        buildGraphInspector = .init()
        previewsUploadService = .init()
        configLoader = .init()
        serverEnvironmentService = .init()
        manifestLoader = .init()
        manifestGraphLoader = .init()
        userInputReader = .init()
        defaultConfigurationFetcher = .init()
        appBundleLoader = .init()
        fileUnarchiver = .init()

        let fileArchiverFactory = MockFileArchivingFactorying()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        subject = ShareCommandService(
            fileHandler: fileHandler,
            fileSystem: fileSystem,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            buildGraphInspector: buildGraphInspector,
            previewsUploadService: previewsUploadService,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            userInputReader: userInputReader,
            defaultConfigurationFetcher: defaultConfigurationFetcher,
            appBundleLoader: appBundleLoader,
            fileArchiverFactory: fileArchiverFactory
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(previewsUploadService)
            .uploadPreview(
                .any,
                path: .any,
                fullHandle: .any,
                serverURL: .any,
                updateProgress: .any
            )
            .willReturn(.test(url: shareURL))

        Matcher.register([GraphTarget].self)
    }

    override func tearDown() {
        xcodeProjectBuildDirectoryLocator = nil
        buildGraphInspector = nil
        previewsUploadService = nil
        configLoader = nil
        serverEnvironmentService = nil
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

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: ["AppOne", "AppTwo"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        )
    }

    func test_share_tuist_project() async throws {
        try await withMockedDependencies { @MainActor in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: "tuist/tuist"))

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
            let graphAppTargetTwo = GraphTarget(
                path: projectPath, target: appTargetTwo, project: project
            )

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
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
                .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
                .willReturn("Debug")

            let iosPath = try temporaryPath()
            let iosDevicePath = try temporaryPath().appending(component: "iphoneos")
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.simulator(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(iosPath)
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.device(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(iosDevicePath)
            try fileHandler.touch(iosPath.appending(component: "App.app"))
            try fileHandler.touch(iosDevicePath.appending(component: "App.app"))

            let visionOSPath = try temporaryPath()
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.simulator(.visionOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(visionOSPath)
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.device(.visionOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(try temporaryPath().appending(component: "visionOS"))
            try fileHandler.touch(visionOSPath.appending(component: "App.app"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(.test())

            // When
            try await subject.run(
                path: nil,
                apps: [],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            )

            // Then
            verify(previewsUploadService)
                .uploadPreview(
                    .any,
                    path: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(Constants.URLs.production),
                    updateProgress: .any
                )
                .called(1)

            assertSnapshot(of: ui(), as: .lines)
        }
    }

    func test_share_tuist_project_when_no_app_found() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let projectPath = try temporaryPath()
        let appTarget: Target = .test(
            name: "AppTarget",
            destinations: [.iPhone],
            productName: "App"
        )
        let project: Project = .test(
            targets: [
                appTarget,
            ]
        )
        let graphAppTarget = GraphTarget(path: projectPath, target: appTarget, project: project)

        given(manifestGraphLoader)
            .load(path: .any, disableSandbox: .any)
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
                ]),
                valueDescription: .any
            )
            .willReturn(graphAppTarget)

        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Debug")

        let iosPath = try temporaryPath()
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.simulator(.iOS)),
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(iosPath)
        given(xcodeProjectBuildDirectoryLocator)
            .locate(
                destinationType: .value(.device(.iOS)),
                projectPath: .any,
                derivedDataPath: .any,
                configuration: .any
            )
            .willReturn(try temporaryPath().appending(component: "iphoneos"))

        given(appBundleLoader)
            .load(.any)
            .willReturn(.test())

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: [],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.noAppsFound(app: "App", configuration: "Debug")
        )
    }

    func test_share_tuist_project_with_a_specified_app() async throws {
        try await withMockedDependencies { @MainActor in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: "tuist/tuist"))

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
            let graphAppTargetTwo = GraphTarget(
                path: projectPath, target: appTargetTwo, project: project
            )

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
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
                .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
                .willReturn("Debug")

            let iosPath = try temporaryPath()
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.simulator(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(iosPath)
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.device(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(try temporaryPath().appending(component: "iphoneos"))
            try fileHandler.touch(iosPath.appending(component: "AppTwo.app"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(
                    .test(
                        infoPlist: .test(
                            version: "1.0.0",
                            bundleId: "dev.tuist.app",
                            supportedPlatforms: [.simulator(.iOS)]
                        )
                    )
                )

            // When
            try await subject.run(
                path: nil,
                apps: ["AppTwo"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            )

            // Then
            verify(previewsUploadService)
                .uploadPreview(
                    .any,
                    path: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(Constants.URLs.production),
                    updateProgress: .any
                )
                .called(1)

            assertSnapshot(of: ui(), as: .lines)
        }
    }

    func test_share_tuist_project_with_a_specified_app_and_json_flag() async throws {
        try await withMockedDependencies {
            // Given
            let projectPath = try temporaryPath()
            let appTarget: Target = .test(
                name: "App"
            )
            let project: Project = .test(
                targets: [
                    appTarget,
                ]
            )
            let graphAppTarget = GraphTarget(path: projectPath, target: appTarget, project: project)

            given(appBundleLoader)
                .load(.any)
                .willReturn(.test())

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
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
                    values: .any,
                    valueDescription: .any
                )
                .willReturn(graphAppTarget)

            given(defaultConfigurationFetcher)
                .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
                .willReturn("Debug")

            let iosPath = try temporaryPath()
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.simulator(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(iosPath)
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.device(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(try temporaryPath().appending(component: "iphoneos"))
            try fileHandler.touch(iosPath.appending(component: "App.app"))

            // When
            try await subject.run(
                path: nil,
                apps: ["AppTwo"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: true
            )

            XCTAssertStandardOutput(pattern: #""bundleIdentifier": "dev.tuist.app""#)
            XCTAssertStandardOutput(pattern: #""displayName": "App""#)
        }
    }

    func test_share_tuist_project_with_a_specified_appclip() async throws {
        try await withMockedDependencies { @MainActor in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: "tuist/tuist"))

            let projectPath = try temporaryPath()
            let appClipTarget: Target = .test(
                name: "AppClip",
                product: .appClip
            )
            let appTarget: Target = .test(name: "App")
            let project: Project = .test(
                targets: [
                    appClipTarget,
                    appTarget,
                ]
            )
            let graphAppClipTarget = GraphTarget(
                path: projectPath, target: appClipTarget, project: project
            )

            given(manifestGraphLoader)
                .load(path: .any, disableSandbox: .any)
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
                    values: .any,
                    valueDescription: .any
                )
                .willReturn(graphAppClipTarget)

            given(defaultConfigurationFetcher)
                .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
                .willReturn("Debug")

            let iosPath = try temporaryPath()
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.simulator(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(iosPath)
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.device(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(try temporaryPath().appending(component: "iphoneos"))
            try fileHandler.touch(iosPath.appending(component: "AppClip.app"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(.test())

            // When
            try await subject.run(
                path: nil,
                apps: ["AppClip"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            )

            // Then
            assertSnapshot(of: ui(), as: .lines)
        }
    }

    func test_share_xcode_app_when_no_app_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

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
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.appNotSpecified
        )
    }

    func test_share_xcode_app_when_multiple_apps_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

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
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        )
    }

    func test_share_xcode_app_when_no_platforms_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

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
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.platformsNotSpecified
        )
    }

    func test_share_xcode_app_when_no_project_or_workspace_not_found() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

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
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.projectOrWorkspaceNotFound(path: path.pathString)
        )
    }

    func test_share_xcode_app() async throws {
        try await withMockedDependencies { @MainActor in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: "tuist/tuist"))

            manifestLoader.reset()

            given(manifestLoader)
                .hasRootManifest(at: .any)
                .willReturn(false)

            let path = try temporaryPath()
            let xcodeprojPath = try temporaryPath().appending(component: "App.xcodeproj")
            try fileHandler.touch(xcodeprojPath)

            let iosPath = try temporaryPath()
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.simulator(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(iosPath)
            given(xcodeProjectBuildDirectoryLocator)
                .locate(
                    destinationType: .value(.device(.iOS)),
                    projectPath: .any,
                    derivedDataPath: .any,
                    configuration: .any
                )
                .willReturn(try temporaryPath().appending(component: "iphoneos"))
            try fileHandler.touch(iosPath.appending(component: "App.app"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(.test())

            // When
            try await subject.run(
                path: path.pathString,
                apps: ["App"],
                configuration: nil,
                platforms: [.iOS],
                derivedDataPath: nil,
                json: false
            )

            // Then
            verify(previewsUploadService)
                .uploadPreview(
                    .any,
                    path: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(Constants.URLs.production),
                    updateProgress: .any
                )
                .called(1)
            assertSnapshot(of: ui(), as: .lines)
        }
    }

    func test_share_different_apps() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let appOne = try temporaryPath().appending(component: "AppOne.app")
        let appTwo = try temporaryPath().appending(component: "AppTwo.app")
        try await fileSystem.makeDirectory(at: appOne)
        try await fileSystem.makeDirectory(at: appTwo)

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
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        )
    }

    func test_share_ipa_and_app_target_name() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let currentPath = try temporaryPath()
        let ipaPath = currentPath.appending(component: "App.ipa")
        try await fileSystem.makeDirectory(at: ipaPath)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: currentPath.pathString,
                apps: [
                    ipaPath.pathString,
                    "AppTarget",
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.multipleAppsSpecified([
                ipaPath.pathString,
                currentPath.appending(component: "AppTarget").pathString,
            ])
        )
    }

    func test_share_app_bundles() async throws {
        try await withMockedDependencies { @MainActor in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: "tuist/tuist"))

            let iosApp = try temporaryPath().appending(components: "iOS", "App.app")
            let visionOSApp = try temporaryPath().appending(components: "visionOs", "App.app")
            try await fileSystem.makeDirectory(at: iosApp)
            let iosIconPath = iosApp.appending(component: "AppIcon60x60@2x.png")
            try await fileSystem.touch(iosIconPath)
            try await fileSystem.makeDirectory(at: visionOSApp)

            given(appBundleLoader)
                .load(.value(iosApp))
                .willReturn(
                    .test(
                        path: iosApp,
                        infoPlist: .test(
                            name: "App",
                            bundleIcons: .test(
                                primaryIcon: .test(
                                    iconFiles: [
                                        "AppIcon60x60",
                                    ]
                                )
                            )
                        )
                    )
                )

            given(appBundleLoader)
                .load(.value(visionOSApp))
                .willReturn(.test(infoPlist: .test(name: "App")))

            // When
            try await subject.run(
                path: nil,
                apps: [
                    iosApp.pathString,
                    visionOSApp.pathString,
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            )

            // Then
            verify(previewsUploadService)
                .uploadPreview(
                    .matching {
                        switch $0 {
                        case let .appBundles(appBundles):
                            return appBundles.count == 2
                        default:
                            return false
                        }
                    },
                    path: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(Constants.URLs.production),
                    updateProgress: .any
                )
                .called(1)

            assertSnapshot(of: ui(), as: .lines)
        }
    }

    func test_share_ipa() async throws {
        try await withMockedDependencies { @MainActor in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: "tuist/tuist"))

            let ipaPath = try temporaryPath().appending(components: "App.ipa")
            try await fileSystem.touch(ipaPath)

            given(appBundleLoader)
                .load(ipa: .value(ipaPath))
                .willReturn(
                    .test(
                        path: ipaPath,
                        infoPlist: .test(
                            version: "1.0.0",
                            name: "App",
                            bundleId: "dev.tuist.app",
                            bundleIcons: .test(
                                primaryIcon: .test(
                                    iconFiles: [
                                        "AppIcon60x60",
                                    ]
                                )
                            )
                        )
                    )
                )

            // When
            try await subject.run(
                path: nil,
                apps: [
                    ipaPath.pathString,
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            )

            // Then
            verify(previewsUploadService)
                .uploadPreview(
                    .matching {
                        switch $0 {
                        case .ipa:
                            return true
                        default:
                            return false
                        }
                    },
                    path: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(Constants.URLs.production),
                    updateProgress: .any
                )
                .called(1)

            assertSnapshot(of: ui(), as: .lines)
        }
    }

    func test_share_multiple_ipas() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let ipaPath = try temporaryPath().appending(components: "App.ipa")
        let watchOSIpaPath = try temporaryPath().appending(component: "WatchOSApp.ipa")
        try await fileSystem.makeDirectory(at: ipaPath)
        try await fileSystem.makeDirectory(at: watchOSIpaPath)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                path: nil,
                apps: [
                    ipaPath.pathString,
                    watchOSIpaPath.pathString,
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false
            ),
            ShareCommandServiceError.multipleAppsSpecified([
                ipaPath.pathString, watchOSIpaPath.pathString,
            ])
        )
    }
}
