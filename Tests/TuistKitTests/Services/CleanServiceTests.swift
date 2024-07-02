import Foundation
import MockableTest
import Path
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import TuistServer
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CleanServiceTests: TuistUnitTestCase {
    private var subject: CleanService!
    private var rootDirectoryLocator: MockRootDirectoryLocator!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var configLoader: MockConfigLoading!
    private var cloudURLService: MockCloudURLServicing!
    private var cleanCacheService: MockCleanCacheServicing!

    override func setUpWithError() throws {
        super.setUp()
        rootDirectoryLocator = MockRootDirectoryLocator()
        cacheDirectoriesProvider = .init()
        manifestFilesLocator = MockManifestFilesLocating()
        configLoader = .init()
        cloudURLService = .init()
        cleanCacheService = .init()

        subject = CleanService(
            fileHandler: FileHandler.shared,
            rootDirectoryLocator: rootDirectoryLocator,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            manifestFilesLocator: manifestFilesLocator,
            configLoader: configLoader,
            cloudURLService: cloudURLService,
            cleanCacheService: cleanCacheService
        )
    }

    override func tearDown() {
        rootDirectoryLocator = nil
        cacheDirectoriesProvider = nil
        manifestFilesLocator = nil
        configLoader = nil
        cloudURLService = nil
        cleanCacheService = nil
        subject = nil
        super.tearDown()
    }

    func test_run_with_category_cleans_category() async throws {
        // Given
        let cachePaths = try createFolders(["tuist/Manifests", "tuist/ProjectDescriptionHelpers"])

        let cachePath = cachePaths[0].parentDirectory.parentDirectory
        given(cacheDirectoriesProvider)
            .cacheDirectory()
            .willReturn(cachePath)
        rootDirectoryLocator.locateStub = cachePath
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

        rootDirectoryLocator.locateStub = localPaths[0].parentDirectory
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

        rootDirectoryLocator.locateStub = localPaths[0].parentDirectory
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
        let cachePath = cachePaths[0].parentDirectory.parentDirectory

        given(cacheDirectoriesProvider)
            .cacheDirectory()
            .willReturn(cachePath)

        let projectPath = try temporaryPath()
        rootDirectoryLocator.locateStub = projectPath
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
}
//
//import MockableTest
//import TuistCore
//import TuistLoader
//import TuistServer
//import TuistSupport
//import XcodeGraph
//import XCTest
//
//@testable import TuistKit
//@testable import TuistSupportTesting
//
//final class RemoteCleanServiceTests: TuistUnitTestCase {
//    private var cloudSessionController: MockCloudSessionControlling!
//    private var cleanCacheService: MockCleanCacheServicing!
//    private var configLoader: MockConfigLoading!
//    private var subject: RemoteCleanService!
//
//    override func setUp() {
//        super.setUp()
//        cloudSessionController = .init()
//        cleanCacheService = .init()
//        configLoader = MockConfigLoading()
//        subject = RemoteCleanService(
//            cloudSessionController: cloudSessionController,
//            cleanCacheService: cleanCacheService,
//            configLoader: configLoader
//        )
//    }
//
//    override func tearDown() {
//        cloudSessionController = nil
//        cleanCacheService = nil
//        configLoader = nil
//        subject = nil
//        super.tearDown()
//    }
//
//    func test_cloud_clean() async throws {
//        // Given
//        let url = URL(string: "https://cloud.com")!
//
//        given(configLoader)
//            .loadConfig(path: .any)
//            .willReturn(
//                Config.test(
//                    cloud: Cloud.test(
//                        url: url,
//                        projectId: "project/slug"
//                    )
//                )
//            )
//
//        given(cleanCacheService)
//            .cleanCache(
//                serverURL: .value(url),
//                fullName: .value("project/slug")
//            )
//            .willReturn(())
//
//        // When
//        try await subject.clean(path: "/some-path")
//
//        // Then
//        XCTAssertPrinterOutputContains("Project was successfully cleaned.")
//    }
//}
