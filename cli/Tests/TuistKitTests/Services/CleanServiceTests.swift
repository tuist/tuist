import FileSystem
import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistTesting

final class CleanServiceTests: TuistUnitTestCase {
    private var subject: CleanService!
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var configLoader: MockConfigLoading!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var cleanCacheService: MockCleanCacheServicing!

    override func setUpWithError() throws {
        super.setUp()
        rootDirectoryLocator = .init()
        cacheDirectoriesProvider = .init()
        manifestFilesLocator = MockManifestFilesLocating()
        configLoader = .init()
        serverEnvironmentService = .init()
        cleanCacheService = .init()

        subject = CleanService(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: rootDirectoryLocator,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            manifestFilesLocator: manifestFilesLocator,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            cleanCacheService: cleanCacheService,
            fileSystem: FileSystem()
        )
    }

    override func tearDown() {
        rootDirectoryLocator = nil
        cacheDirectoriesProvider = nil
        manifestFilesLocator = nil
        configLoader = nil
        serverEnvironmentService = nil
        cleanCacheService = nil
        subject = nil
        super.tearDown()
    }

    func test_run_with_category_cleans_category() async throws {
        // Given
        let rootDirectory = try temporaryPath()
        let cachePaths = try await createFiles([
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
            try await self.fileSystem.exists($0)
        }
        XCTAssertFalse(cachePathsExists[0])
        XCTAssertTrue(cachePathsExists[1])
    }

    func test_run_with_dependencies_cleans_dependencies() async throws {
        // Given
        let rootDirectory = try temporaryPath()
        let localPaths = try await createFiles([
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
            try await self.fileSystem.exists($0)
        }
        XCTAssertFalse(localPathsExists[0])
        XCTAssertTrue(localPathsExists[1])
    }

    func test_run_with_dependencies_cleans_dependencies_when_package_is_in_root() async throws {
        // Given
        let rootDirectory = try temporaryPath()
        let localPaths = try await createFiles([
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
            try await self.fileSystem.exists($0)
        }
        XCTAssertFalse(localPathsExists[0])
        XCTAssertTrue(localPathsExists[1])
    }

    func test_run_without_category_cleans_all() async throws {
        // Given
        let cachePaths = try await createFiles(["tuist/Manifests/hash"])

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(cachePaths[0].parentDirectory)

        let projectPath = try temporaryPath()
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
        XCTAssertFalse(cachePathExists)
        let swiftPackageManagerBuildFileExists = try await fileSystem.exists(
            swiftPackageManagerBuildFile
        )
        XCTAssertFalse(swiftPackageManagerBuildFileExists)
    }

    func test_run_with_remote() async throws {
        try await withMockedDependencies {
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
                .willReturn(try temporaryPath())

            let projectPath = try temporaryPath()
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
            XCTAssertStandardOutput(pattern: "Successfully cleaned the remote storage.")
        }
    }
}
