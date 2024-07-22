import FileSystem
import Foundation
import MockableTest
import Path
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CleanServiceTests: TuistUnitTestCase {
    private var subject: CleanService!
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var configLoader: MockConfigLoading!
    private var serverURLService: MockServerURLServicing!
    private var cleanCacheService: MockCleanCacheServicing!

    override func setUpWithError() throws {
        super.setUp()
        rootDirectoryLocator = .init()
        cacheDirectoriesProvider = .init()
        manifestFilesLocator = MockManifestFilesLocating()
        configLoader = .init()
        serverURLService = .init()
        cleanCacheService = .init()

        subject = CleanService(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: rootDirectoryLocator,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            manifestFilesLocator: manifestFilesLocator,
            configLoader: configLoader,
            serverURLService: serverURLService,
            cleanCacheService: cleanCacheService,
            fileSystem: FileSystem()
        )
    }

    override func tearDown() {
        rootDirectoryLocator = nil
        cacheDirectoriesProvider = nil
        manifestFilesLocator = nil
        configLoader = nil
        serverURLService = nil
        cleanCacheService = nil
        subject = nil
        super.tearDown()
    }

    func test_run_with_category_cleans_category() async throws {
        // Given
        let cachePaths = try createFolders(["tuist/Manifests", "tuist/ProjectDescriptionHelpers"])

        let cachePath = cachePaths[0].parentDirectory.parentDirectory
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.manifests))
            .willReturn(cachePaths[0])
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.projectDescriptionHelpers))
            .willReturn(cachePaths[1])
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(cachePath)
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
        XCTAssertFalse(FileHandler.shared.exists(cachePaths[0]))
        XCTAssertTrue(FileHandler.shared.exists(cachePaths[1]))
    }

    func test_run_with_dependencies_cleans_dependencies() async throws {
        // Given
        let localPaths = try createFolders(["Tuist/.build", "Tuist/ProjectDescriptionHelpers"])

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(localPaths[0].parentDirectory)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                localPaths[1].parentDirectory
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
        XCTAssertFalse(FileHandler.shared.exists(localPaths[0]))
        XCTAssertTrue(FileHandler.shared.exists(localPaths[1]))
    }

    func test_run_with_dependencies_cleans_dependencies_when_package_is_in_root() async throws {
        // Given
        let localPaths = try createFolders([".build", "Tuist/ProjectDescriptionHelpers"])

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(localPaths[0].parentDirectory)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                localPaths[0].parentDirectory
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
        XCTAssertFalse(FileHandler.shared.exists(localPaths[0]))
        XCTAssertTrue(FileHandler.shared.exists(localPaths[1]))
    }

    func test_run_without_category_cleans_all() async throws {
        // Given
        let cachePaths = try createFolders(["tuist/Manifests"])

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(cachePaths[0])

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

        // When
        try await subject.run(
            categories: TuistCleanCategory.allCases,
            remote: false,
            path: nil
        )

        // Then
        XCTAssertFalse(FileHandler.shared.exists(cachePaths[0]))
        XCTAssertFalse(FileHandler.shared.exists(swiftPackageManagerBuildPath))
    }

    func test_run_with_remote() async throws {
        // Given
        let url = URL(string: "https://cloud.com")!

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                Config.test(
                    fullHandle: "tuist/tuist",
                    url: url
                )
            )

        given(serverURLService)
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
