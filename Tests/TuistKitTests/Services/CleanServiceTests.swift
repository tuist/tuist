import Foundation
import MockableTest
import Path
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CleanServiceTests: TuistUnitTestCase {
    private var subject: CleanService!
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var manifestFilesLocator: MockManifestFilesLocating!

    override func setUpWithError() throws {
        super.setUp()
        rootDirectoryLocator = .init()
        cacheDirectoriesProvider = .init()
        manifestFilesLocator = MockManifestFilesLocating()

        subject = CleanService(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: rootDirectoryLocator,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            manifestFilesLocator: manifestFilesLocator
        )
    }

    override func tearDown() {
        rootDirectoryLocator = nil
        cacheDirectoriesProvider = nil
        manifestFilesLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_run_with_category_cleans_category() throws {
        // Given
        let cachePaths = try createFolders(["tuist/Manifests", "tuist/ProjectDescriptionHelpers"])

        let cachePath = cachePaths[0].parentDirectory.parentDirectory
        given(cacheDirectoriesProvider)
            .cacheDirectory()
            .willReturn(cachePath)
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(cachePath)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)

        // When
        try subject.run(categories: [TuistCleanCategory.global(.manifests)], path: nil)

        // Then
        XCTAssertFalse(FileHandler.shared.exists(cachePaths[0]))
        XCTAssertTrue(FileHandler.shared.exists(cachePaths[1]))
    }

    func test_run_with_dependencies_cleans_dependencies() throws {
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
        try subject.run(categories: [TuistCleanCategory.dependencies], path: nil)

        // Then
        XCTAssertFalse(FileHandler.shared.exists(localPaths[0]))
        XCTAssertTrue(FileHandler.shared.exists(localPaths[1]))
    }

    func test_run_with_dependencies_cleans_dependencies_when_package_is_in_root() throws {
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
        try subject.run(categories: [TuistCleanCategory.dependencies], path: nil)

        // Then
        XCTAssertFalse(FileHandler.shared.exists(localPaths[0]))
        XCTAssertTrue(FileHandler.shared.exists(localPaths[1]))
    }

    func test_run_without_category_cleans_all() throws {
        // Given
        let cachePaths = try createFolders(["tuist/Manifests"])
        let cachePath = cachePaths[0].parentDirectory.parentDirectory

        given(cacheDirectoriesProvider)
            .cacheDirectory()
            .willReturn(cachePath)

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
        try subject.run(categories: TuistCleanCategory.allCases, path: nil)

        // Then
        XCTAssertFalse(FileHandler.shared.exists(cachePaths[0]))
        XCTAssertFalse(FileHandler.shared.exists(swiftPackageManagerBuildPath))
    }
}
