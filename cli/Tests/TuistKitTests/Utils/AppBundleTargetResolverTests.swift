import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfigLoader
import TuistCore
import TuistLoader
import TuistSupport
import TuistTesting
import TuistUserInputReader
import XcodeGraph

@testable import TuistKit

struct AppBundleTargetResolverTests {
    private let manifestLoader = MockManifestLoading()
    private let manifestGraphLoader = MockManifestGraphLoading()
    private let configLoader = MockConfigLoading()
    private let defaultConfigurationFetcher = MockDefaultConfigurationFetching()
    private let userInputReader = MockUserInputReading()
    private let fileSystem = FileSystem()
    private let subject: AppBundleTargetResolver

    init() {
        subject = AppBundleTargetResolver(
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            configLoader: configLoader,
            defaultConfigurationFetcher: defaultConfigurationFetcher,
            userInputReader: userInputReader,
            fileSystem: fileSystem
        )

        Matcher.register([GraphTarget].self)
    }

    // MARK: - Manifest resolution

    @Test(.inTemporaryDirectory)
    func resolve_from_manifest_with_single_matching_target() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        let appTarget: Target = .test(
            name: "App",
            destinations: [.iPhone],
            productName: "App"
        )
        let project: Project = .test(targets: [appTarget])

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        given(manifestGraphLoader)
            .load(path: .any, disableSandbox: .any)
            .willReturn((
                .test(projects: [path: project]),
                [],
                MapperEnvironment(),
                []
            ))

        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Debug")

        let result = try await subject.resolve(
            app: "App",
            path: path,
            configuration: nil,
            platforms: [],
            derivedDataPath: nil
        )

        #expect(result.app == "App")
        #expect(result.configuration == "Debug")
        #expect(result.platforms == [.iOS])
    }

    @Test(.inTemporaryDirectory)
    func resolve_from_manifest_with_explicit_platforms() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        let appTarget: Target = .test(
            name: "App",
            destinations: [.iPhone, .appleVision],
            productName: "App"
        )
        let project: Project = .test(targets: [appTarget])

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        given(manifestGraphLoader)
            .load(path: .any, disableSandbox: .any)
            .willReturn((
                .test(projects: [path: project]),
                [],
                MapperEnvironment(),
                []
            ))

        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Release")

        let result = try await subject.resolve(
            app: "App",
            path: path,
            configuration: "Release",
            platforms: [.iOS],
            derivedDataPath: nil
        )

        #expect(result.app == "App")
        #expect(result.configuration == "Release")
        #expect(result.platforms == [.iOS])
    }

    @Test(.inTemporaryDirectory)
    func resolve_from_manifest_with_multiple_targets_prompts_user() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        let appTarget: Target = .test(name: "App", destinations: [.iPhone], productName: "App")
        let appTarget2: Target = .test(name: "AppTwo", destinations: [.iPhone], productName: "AppTwo")
        let project: Project = .test(targets: [appTarget, appTarget2])
        let graphAppTarget = GraphTarget(path: path, target: appTarget, project: project)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        given(manifestGraphLoader)
            .load(path: .any, disableSandbox: .any)
            .willReturn((
                .test(projects: [path: project]),
                [],
                MapperEnvironment(),
                []
            ))

        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Debug")

        given(userInputReader)
            .readValue(asking: .any, values: .any, valueDescription: .any)
            .willReturn(graphAppTarget)

        let result = try await subject.resolve(
            app: nil,
            path: path,
            configuration: nil,
            platforms: [],
            derivedDataPath: nil
        )

        #expect(result.app == "App")
        verify(userInputReader)
            .readValue(asking: .any, values: Parameter<[GraphTarget]>.any, valueDescription: .any)
            .called(1)
    }

    @Test(.inTemporaryDirectory)
    func resolve_from_manifest_throws_when_no_matching_targets() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(true)

        let frameworkTarget: Target = .test(name: "Framework", product: .framework)
        let project: Project = .test(targets: [frameworkTarget])

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        given(manifestGraphLoader)
            .load(path: .any, disableSandbox: .any)
            .willReturn((
                .test(projects: [path: project]),
                [],
                MapperEnvironment(),
                []
            ))

        given(defaultConfigurationFetcher)
            .fetch(configuration: .any, defaultConfiguration: .any, graph: .any)
            .willReturn("Debug")

        await #expect(
            throws: AppBundleTargetResolverError.noAppsFound(app: "MyApp", configuration: "Debug")
        ) {
            try await subject.resolve(
                app: "MyApp",
                path: path,
                configuration: nil,
                platforms: [],
                derivedDataPath: nil
            )
        }
    }

    // MARK: - Xcode project resolution

    @Test(.inTemporaryDirectory)
    func resolve_from_xcode_project() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeprojPath = path.appending(component: "App.xcodeproj")
        try await fileSystem.makeDirectory(at: xcodeprojPath)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        let result = try await subject.resolve(
            app: "App",
            path: path,
            configuration: nil,
            platforms: [.iOS],
            derivedDataPath: nil
        )

        #expect(result.app == "App")
        #expect(result.workspacePath == xcodeprojPath)
        #expect(result.configuration == "Debug")
        #expect(result.platforms == [.iOS])
    }

    @Test(.inTemporaryDirectory)
    func resolve_from_xcode_project_prefers_workspace() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = path.appending(component: "App.xcworkspace")
        let xcodeprojPath = path.appending(component: "App.xcodeproj")
        try await fileSystem.makeDirectory(at: workspacePath)
        try await fileSystem.makeDirectory(at: xcodeprojPath)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        let result = try await subject.resolve(
            app: "App",
            path: path,
            configuration: "Release",
            platforms: [.macOS],
            derivedDataPath: nil
        )

        #expect(result.workspacePath == workspacePath)
        #expect(result.configuration == "Release")
    }

    @Test(.inTemporaryDirectory)
    func resolve_from_xcode_project_throws_when_no_app_specified() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        await #expect(throws: AppBundleTargetResolverError.appNotSpecified) {
            try await subject.resolve(
                app: nil,
                path: path,
                configuration: nil,
                platforms: [.iOS],
                derivedDataPath: nil
            )
        }
    }

    @Test(.inTemporaryDirectory)
    func resolve_from_xcode_project_throws_when_no_platforms() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        await #expect(throws: AppBundleTargetResolverError.platformsNotSpecified) {
            try await subject.resolve(
                app: "App",
                path: path,
                configuration: nil,
                platforms: [],
                derivedDataPath: nil
            )
        }
    }

    @Test(.inTemporaryDirectory)
    func resolve_from_xcode_project_throws_when_no_project_found() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        given(manifestLoader)
            .hasRootManifest(at: .any)
            .willReturn(false)

        await #expect(
            throws: AppBundleTargetResolverError.projectOrWorkspaceNotFound(path: path.pathString)
        ) {
            try await subject.resolve(
                app: "App",
                path: path,
                configuration: nil,
                platforms: [.iOS],
                derivedDataPath: nil
            )
        }
    }
}
