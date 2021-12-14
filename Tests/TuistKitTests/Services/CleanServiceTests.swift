import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CleanServiceTests: TuistUnitTestCase {
    private var subject: CleanService!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProvider!

    override func setUp() {
        super.setUp()
        let mockCacheDirectoriesProvider = try! MockCacheDirectoriesProvider()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider

        subject = CleanService(
            cacheDirectoryProviderFactory: MockCacheDirectoriesProviderFactory(provider: mockCacheDirectoriesProvider)
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_run_with_category_cleans_category() throws {
        // Given
        let cachePaths = try createFolders(["Cache", "Cache/BuildCache", "Cache/Manifests", "Cache/TestsCache"])
        let cachePath = cachePaths[0]
        for path in cachePaths {
            let correctlyCreated = FileManager.default.fileExists(atPath: path.pathString)
            XCTAssertTrue(correctlyCreated, "Test setup is not properly done. Folder \(path.pathString) should exist")
        }
        cacheDirectoriesProvider.cacheDirectoryStub = cachePath

        // When
        try subject.run(categories: [.global(.builds), .global(.tests)], path: nil)

        // Then
        let buildsExists = FileManager.default.fileExists(atPath: cachePaths[1].pathString)
        XCTAssertFalse(buildsExists, "Cache folder at path \(cachePaths[1]) should have been deleted by the test.")
        let manifestsExists = FileManager.default.fileExists(atPath: cachePaths[2].pathString)
        XCTAssertTrue(
            manifestsExists,
            "Cache folder at path \(cachePaths[2].pathString) should not have been deleted by the test."
        )
        let testsExists = FileManager.default.fileExists(atPath: cachePaths[3].pathString)
        XCTAssertFalse(testsExists, "Cache folder at path \(cachePaths[3].pathString) should not have been deleted by the test.")
    }

    func test_run_without_category_cleans_all() throws {
        // Given
        let cachePaths = try createFolders(["Cache", "Cache/BuildCache", "Cache/Manifests", "Cache/TestsCache"])
        let cachePath = cachePaths[0]
        for path in cachePaths {
            let correctlyCreated = FileManager.default.fileExists(atPath: path.pathString)
            XCTAssertTrue(correctlyCreated, "Test setup is not properly done. Folder \(path.pathString) should exist")
        }
        cacheDirectoriesProvider.cacheDirectoryStub = cachePath
        let projectPath = try temporaryPath()
        let dependenciesPath = projectPath.appending(
            components: Constants.tuistDirectoryName,
            Constants.DependenciesDirectory.name
        )
        try fileHandler.createFolder(dependenciesPath)

        // When
        try subject.run(categories: CleanCategory.allCases, path: nil)

        // Then
        let buildsExists = FileManager.default.fileExists(atPath: cachePaths[1].pathString)
        XCTAssertFalse(buildsExists, "Cache folder at path \(cachePaths[1]) should have been deleted by the test.")
        let manifestsExists = FileManager.default.fileExists(atPath: cachePaths[2].pathString)
        XCTAssertFalse(manifestsExists, "Cache folder at path \(cachePaths[2].pathString) should have been deleted by the test.")
        let testsExists = FileManager.default.fileExists(atPath: cachePaths[3].pathString)
        XCTAssertFalse(testsExists, "Cache folder at path \(cachePaths[3].pathString) should not have been deleted by the test.")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dependenciesPath.pathString),
            "Cache folder at path \(dependenciesPath) should have been deleted by the test."
        )
    }
}
