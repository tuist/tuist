import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import SnapshotTesting
import Testing
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct ShareCommandServiceTests {
    private let subject: ShareCommandService
    private let xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocating
    private let buildGraphInspector: MockBuildGraphInspecting
    private let previewsUploadService: MockPreviewsUploadServicing
    private let configLoader: MockConfigLoading
    private let serverEnvironmentService: MockServerEnvironmentServicing
    private let manifestLoader: MockManifestLoading
    private let manifestGraphLoader: MockManifestGraphLoading
    private let userInputReader: MockUserInputReading
    private let defaultConfigurationFetcher: MockDefaultConfigurationFetching
    private let appBundleLoader: MockAppBundleLoading
    private let fileUnarchiver: MockFileUnarchiving
    private let fileArchiverFactory: MockFileArchivingFactorying
    private let fileSystem = FileSystem()
    private let shareURL: URL = .test()

    init() {
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
        fileArchiverFactory = MockFileArchivingFactorying()

        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        subject = ShareCommandService(
            fileHandler: FileHandler.shared,
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
                track: .any,
                updateProgress: .any
            )
            .willReturn(.test(url: shareURL))

        Matcher.register([GraphTarget].self)
    }

    @Test func share_tuist_project_when_multiple_apps_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        ) {
            try await subject.run(
                path: nil,
                apps: ["AppOne", "AppTwo"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_tuist_project() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

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

        let iosPath = projectPath.appending(component: "ios-simulator")
        let iosDevicePath = projectPath.appending(component: "iphoneos")
        try await fileSystem.makeDirectory(at: iosPath)
        try await fileSystem.makeDirectory(at: iosDevicePath)

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
        try await fileSystem.makeDirectory(at: iosPath.appending(component: "App.app"))
        try await fileSystem.makeDirectory(at: iosDevicePath.appending(component: "App.app"))

        let visionOSPath = projectPath.appending(component: "visionos-simulator")
        let visionOSDevicePath = projectPath.appending(component: "visionOS")
        try await fileSystem.makeDirectory(at: visionOSPath)
        try await fileSystem.makeDirectory(at: visionOSDevicePath)

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
            .willReturn(visionOSDevicePath)
        try await fileSystem.makeDirectory(at: visionOSPath.appending(component: "App.app"))

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
            json: false,
            track: nil
        )

        // Then
        verify(previewsUploadService)
            .uploadPreview(
                .any,
                path: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
                track: .value(nil),
                updateProgress: .any
            )
            .called(1)

        assertSnapshot(of: ui(), as: .lines)
    }

    @Test(.inTemporaryDirectory)
    func share_tuist_project_when_no_app_found() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

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

        let iosPath = projectPath.appending(component: "ios-simulator")
        let iosDevicePath = projectPath.appending(component: "iphoneos")
        try await fileSystem.makeDirectory(at: iosPath)
        try await fileSystem.makeDirectory(at: iosDevicePath)

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

        given(appBundleLoader)
            .load(.any)
            .willReturn(.test())

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.noAppsFound(app: "App", configuration: "Debug")
        ) {
            try await subject.run(
                path: nil,
                apps: [],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_tuist_project_with_a_specified_app() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

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

        let iosPath = projectPath.appending(component: "ios-simulator")
        let iosDevicePath = projectPath.appending(component: "iphoneos")
        try await fileSystem.makeDirectory(at: iosPath)
        try await fileSystem.makeDirectory(at: iosDevicePath)

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
        try await fileSystem.makeDirectory(at: iosPath.appending(component: "AppTwo.app"))

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
            json: false,
            track: nil
        )

        // Then
        verify(previewsUploadService)
            .uploadPreview(
                .any,
                path: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
                track: .value(nil),
                updateProgress: .any
            )
            .called(1)

        assertSnapshot(of: ui(), as: .lines)
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_tuist_project_with_a_specified_app_and_json_flag() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)

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

        let iosPath = projectPath.appending(component: "ios-simulator")
        let iosDevicePath = projectPath.appending(component: "iphoneos")
        try await fileSystem.makeDirectory(at: iosPath)
        try await fileSystem.makeDirectory(at: iosDevicePath)

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
        try await fileSystem.makeDirectory(at: iosPath.appending(component: "App.app"))

        // When
        try await subject.run(
            path: nil,
            apps: ["AppTwo"],
            configuration: nil,
            platforms: [],
            derivedDataPath: nil,
            json: true,
            track: nil
        )

        TuistTest.expectLogs(#""bundleIdentifier": "dev.tuist.app""#)
        TuistTest.expectLogs(#""displayName": "App""#)
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_tuist_project_with_a_specified_appclip() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

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

        let iosPath = projectPath.appending(component: "ios-simulator")
        let iosDevicePath = projectPath.appending(component: "iphoneos")
        try await fileSystem.makeDirectory(at: iosPath)
        try await fileSystem.makeDirectory(at: iosDevicePath)

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
        try await fileSystem.makeDirectory(at: iosPath.appending(component: "AppClip.app"))

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
            json: false,
            track: nil
        )

        // Then
        assertSnapshot(of: ui(), as: .lines)
    }

    @Test func share_xcode_app_when_no_app_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.appNotSpecified
        ) {
            try await subject.run(
                path: nil,
                apps: [],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test func share_xcode_app_when_multiple_apps_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        ) {
            try await subject.run(
                path: nil,
                apps: ["AppOne", "AppTwo"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test func share_xcode_app_when_no_platforms_specified() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.platformsNotSpecified
        ) {
            try await subject.run(
                path: nil,
                apps: ["App"],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test(.inTemporaryDirectory)
    func share_xcode_app_when_no_project_or_workspace_not_found() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.projectOrWorkspaceNotFound(path: path.pathString)
        ) {
            try await subject.run(
                path: path.pathString,
                apps: ["App"],
                configuration: nil,
                platforms: [.iOS],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_xcode_app() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        manifestLoader.reset()

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        let xcodeprojPath = path.appending(component: "App.xcodeproj")
        try await fileSystem.makeDirectory(at: xcodeprojPath)

        let iosPath = path.appending(component: "ios-simulator")
        let iosDevicePath = path.appending(component: "iphoneos")
        try await fileSystem.makeDirectory(at: iosPath)
        try await fileSystem.makeDirectory(at: iosDevicePath)

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
        try await fileSystem.makeDirectory(at: iosPath.appending(component: "App.app"))

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
            json: false,
            track: nil
        )

        // Then
        verify(previewsUploadService)
            .uploadPreview(
                .any,
                path: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
                track: .value(nil),
                updateProgress: .any
            )
            .called(1)
        assertSnapshot(of: ui(), as: .lines)
    }

    @Test(.inTemporaryDirectory)
    func share_different_apps() async throws {
        // Given
        let tempPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let appOne = tempPath.appending(component: "AppOne.app")
        let appTwo = tempPath.appending(component: "AppTwo.app")
        try await fileSystem.makeDirectory(at: appOne)
        try await fileSystem.makeDirectory(at: appTwo)

        given(appBundleLoader)
            .load(.value(appOne))
            .willReturn(.test(infoPlist: .test(name: "AppOne")))

        given(appBundleLoader)
            .load(.value(appTwo))
            .willReturn(.test(infoPlist: .test(name: "AppTwo")))

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.multipleAppsSpecified(["AppOne", "AppTwo"])
        ) {
            try await subject.run(
                path: nil,
                apps: [
                    appOne.pathString,
                    appTwo.pathString,
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test(.inTemporaryDirectory)
    func share_ipa_and_app_target_name() async throws {
        // Given
        let currentPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let ipaPath = currentPath.appending(component: "App.ipa")
        try await fileSystem.makeDirectory(at: ipaPath)

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.multipleAppsSpecified([
                ipaPath.pathString,
                currentPath.appending(component: "AppTarget").pathString,
            ])
        ) {
            try await subject.run(
                path: currentPath.pathString,
                apps: [
                    ipaPath.pathString,
                    "AppTarget",
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_app_bundles() async throws {
        // Given
        let tempPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let iosApp = tempPath.appending(components: "iOS", "App.app")
        let visionOSApp = tempPath.appending(components: "visionOs", "App.app")
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
            json: false,
            track: nil
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
                track: .value(nil),
                updateProgress: .any
            )
            .called(1)

        assertSnapshot(of: ui(), as: .lines)
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_ipa() async throws {
        // Given
        let tempPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let ipaPath = tempPath.appending(components: "App.ipa")
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
            json: false,
            track: nil
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
                track: .value(nil),
                updateProgress: .any
            )
            .called(1)

        assertSnapshot(of: ui(), as: .lines)
    }

    @Test(.inTemporaryDirectory)
    func share_multiple_ipas() async throws {
        // Given
        let tempPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let ipaPath = tempPath.appending(components: "App.ipa")
        let watchOSIpaPath = tempPath.appending(component: "WatchOSApp.ipa")
        try await fileSystem.makeDirectory(at: ipaPath)
        try await fileSystem.makeDirectory(at: watchOSIpaPath)

        // When / Then
        await #expect(
            throws: ShareCommandServiceError.multipleAppsSpecified([
                ipaPath.pathString, watchOSIpaPath.pathString,
            ])
        ) {
            try await subject.run(
                path: nil,
                apps: [
                    ipaPath.pathString,
                    watchOSIpaPath.pathString,
                ],
                configuration: nil,
                platforms: [],
                derivedDataPath: nil,
                json: false,
                track: nil
            )
        }
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_with_track() async throws {
        // Given
        let tempPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let iosApp = tempPath.appending(components: "iOS", "App.app")
        try await fileSystem.makeDirectory(at: iosApp)

        given(appBundleLoader)
            .load(.value(iosApp))
            .willReturn(
                .test(
                    path: iosApp,
                    infoPlist: .test(name: "App")
                )
            )

        // When
        try await subject.run(
            path: nil,
            apps: [iosApp.pathString],
            configuration: nil,
            platforms: [],
            derivedDataPath: nil,
            json: false,
            track: "beta"
        )

        // Then
        verify(previewsUploadService)
            .uploadPreview(
                .any,
                path: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
                track: .value("beta"),
                updateProgress: .any
            )
            .called(1)

        assertSnapshot(of: ui(), as: .lines)
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory)
    func share_ipa_with_track() async throws {
        // Given
        let tempPath = try #require(FileSystem.temporaryTestDirectory)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        let ipaPath = tempPath.appending(components: "App.ipa")
        try await fileSystem.touch(ipaPath)

        given(appBundleLoader)
            .load(ipa: .value(ipaPath))
            .willReturn(
                .test(
                    path: ipaPath,
                    infoPlist: .test(
                        version: "1.0.0",
                        name: "App",
                        bundleId: "dev.tuist.app"
                    )
                )
            )

        // When
        try await subject.run(
            path: nil,
            apps: [ipaPath.pathString],
            configuration: nil,
            platforms: [],
            derivedDataPath: nil,
            json: false,
            track: "nightly"
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
                track: .value("nightly"),
                updateProgress: .any
            )
            .called(1)

        assertSnapshot(of: ui(), as: .lines)
    }
}
