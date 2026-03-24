import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCache
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistLoader
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct CleanServiceTests {
    private var subject: CleanService!
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var configLoader: MockConfigLoading!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var cleanCacheService: MockCleanCacheServicing!
    private var cleanProjectCacheService: MockCleanProjectCacheServicing!
    private var getCacheEndpointsService: MockGetCacheEndpointsServicing!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private let fileSystem = FileSystem()
    private let fileHandler = FileHandler.shared

    init() throws {
        rootDirectoryLocator = .init()
        cacheDirectoriesProvider = .init()
        manifestFilesLocator = MockManifestFilesLocating()
        configLoader = .init()
        serverEnvironmentService = .init()
        cleanCacheService = .init()
        cleanProjectCacheService = .init()
        getCacheEndpointsService = .init()
        serverAuthenticationController = .init()

        subject = CleanService(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: rootDirectoryLocator,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            manifestFilesLocator: manifestFilesLocator,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            cleanCacheService: cleanCacheService,
            cleanProjectCacheService: cleanProjectCacheService,
            getCacheEndpointsService: getCacheEndpointsService,
            serverAuthenticationController: serverAuthenticationController,
            fileSystem: FileSystem()
        )
    }

    @Test(.inTemporaryDirectory) func run_with_category_cleans_category() async throws {
        // Given
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let cachePaths = try await TuistTest.createFiles([
            "tuist/Manifests/manifest.json", "tuist/ProjectDescriptionHelpers/File.swift",
        ])

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.manifests))
            .willReturn(cachePaths[0].parentDirectory)
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.projectDescriptionHelpers))
            .willReturn(cachePaths[1].parentDirectory)
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(rootDirectory)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)

        // When
        try await subject.run(
            categories: [TuistCleanCategory.global(.manifests)],
            remote: false,
            path: nil
        )

        // Then
        let cachePathsExists = try await cachePaths.concurrentMap {
            try await fileSystem.exists($0)
        }
        #expect(!cachePathsExists[0])
        #expect(cachePathsExists[1])
    }

    @Test(.inTemporaryDirectory) func run_with_dependencies_cleans_dependencies() async throws {
        // Given
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let localPaths = try await TuistTest.createFiles([
            "Tuist/.build/file", "Tuist/ProjectDescriptionHelpers/File.swift",
        ])

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(rootDirectory)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                rootDirectory
                    .appending(components: "Tuist", Constants.SwiftPackageManager.packageSwiftName)
            )

        let cachePath = rootDirectory
        given(cacheDirectoriesProvider)
            .cacheDirectory()
            .willReturn(cachePath)

        // When
        try await subject.run(
            categories: [TuistCleanCategory.dependencies],
            remote: false,
            path: nil
        )

        // Then
        let localPathsExists = try await localPaths.concurrentMap {
            try await fileSystem.exists($0)
        }
        #expect(!localPathsExists[0])
        #expect(localPathsExists[1])
    }

    @Test(.inTemporaryDirectory) func run_with_dependencies_cleans_dependencies_when_package_is_in_root() async throws {
        // Given
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let localPaths = try await TuistTest.createFiles([
            ".build/file", "Tuist/ProjectDescriptionHelpers/file",
        ])

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(rootDirectory)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                rootDirectory
                    .appending(component: Constants.SwiftPackageManager.packageSwiftName)
            )

        let cachePath = localPaths[0].parentDirectory.parentDirectory
        given(cacheDirectoriesProvider)
            .cacheDirectory()
            .willReturn(cachePath)

        // When
        try await subject.run(
            categories: [TuistCleanCategory.dependencies],
            remote: false,
            path: nil
        )

        // Then
        let localPathsExists = try await localPaths.concurrentMap {
            try await fileSystem.exists($0)
        }
        #expect(!localPathsExists[0])
        #expect(localPathsExists[1])
    }

    @Test(.inTemporaryDirectory) func run_without_category_cleans_all() async throws {
        // Given
        let cachePaths = try await TuistTest.createFiles(["tuist/Manifests/hash"])

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(cachePaths[0].parentDirectory)

        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(projectPath)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath
                    .appending(component: Constants.SwiftPackageManager.packageSwiftName)
            )
        let swiftPackageManagerBuildPath = projectPath.appending(
            components: Constants.SwiftPackageManager.packageBuildDirectoryName
        )
        try fileHandler.createFolder(swiftPackageManagerBuildPath)
        let swiftPackageManagerBuildFile = swiftPackageManagerBuildPath.appending(component: "file")
        try await fileSystem.touch(swiftPackageManagerBuildFile)

        // When
        try await subject.run(
            categories: TuistCleanCategory.allCases,
            remote: false,
            path: nil
        )

        // Then
        let cachePathExists = try await fileSystem.exists(cachePaths[0])
        #expect(!cachePathExists)
        let swiftPackageManagerBuildFileExists = try await fileSystem.exists(
            swiftPackageManagerBuildFile
        )
        #expect(!swiftPackageManagerBuildFileExists)
    }

    @Test(.inTemporaryDirectory) func run_with_remote_legacy() async throws {
        try await withMockedEnvironment {
            try await withMockedDependencies {
                Environment.mocked?.variables["TUIST_LEGACY_MODULE_CACHE"] = "1"
                // Given
                let url = URL(string: "https://cloud.com")!

                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(
                        Tuist.test(
                            fullHandle: "tuist/tuist",
                            url: url
                        )
                    )

                given(serverEnvironmentService)
                    .url(configServerURL: .any)
                    .willReturn(url)

                given(cleanCacheService)
                    .cleanCache(
                        serverURL: .value(url),
                        fullHandle: .value("tuist/tuist")
                    )
                    .willReturn(())

                given(cacheDirectoriesProvider)
                    .cacheDirectory(for: .any)
                    .willReturn(try #require(FileSystem.temporaryTestDirectory))

                let projectPath = try #require(FileSystem.temporaryTestDirectory)
                given(rootDirectoryLocator)
                    .locate(from: .any)
                    .willReturn(projectPath)
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willReturn(nil)

                // When
                try await subject.run(
                    categories: TuistCleanCategory.allCases,
                    remote: true,
                    path: nil
                )

                // Then
                verify(cleanCacheService)
                    .cleanCache(serverURL: .any, fullHandle: .any)
                    .called(1)
                TuistTest.expectLogs("Successfully cleaned the remote storage.")
            }
        }
    }

    @Test(.inTemporaryDirectory) func run_with_remote() async throws {
        try await withMockedEnvironment {
            try await withMockedDependencies {
                Environment.mocked?.variables["TUIST_LEGACY_MODULE_CACHE"] = "0"
                // Given
                let serverURL = URL(string: "https://cloud.com")!
                let cacheEndpoint = "https://cache1.cloud.com"

                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(
                        Tuist.test(
                            fullHandle: "tuist/tuist",
                            url: serverURL
                        )
                    )

                given(serverEnvironmentService)
                    .url(configServerURL: .any)
                    .willReturn(serverURL)

                given(getCacheEndpointsService)
                    .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value("tuist"))
                    .willReturn([cacheEndpoint])

                given(cleanProjectCacheService)
                    .cleanProjectCache(
                        accountHandle: .value("tuist"),
                        projectHandle: .value("tuist"),
                        serverURL: .any,
                        authenticationURL: .value(serverURL),
                        serverAuthenticationController: .any
                    )
                    .willReturn(())

                given(cacheDirectoriesProvider)
                    .cacheDirectory(for: .any)
                    .willReturn(try #require(FileSystem.temporaryTestDirectory))

                let projectPath = try #require(FileSystem.temporaryTestDirectory)
                given(rootDirectoryLocator)
                    .locate(from: .any)
                    .willReturn(projectPath)
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willReturn(nil)

                // When
                try await subject.run(
                    categories: TuistCleanCategory.allCases,
                    remote: true,
                    path: nil
                )

                // Then
                verify(cleanProjectCacheService)
                    .cleanProjectCache(
                        accountHandle: .any,
                        projectHandle: .any,
                        serverURL: .any,
                        authenticationURL: .any,
                        serverAuthenticationController: .any
                    )
                    .called(1)
                TuistTest.expectLogs("Successfully cleaned the remote storage.")
            }
        }
    }
}
