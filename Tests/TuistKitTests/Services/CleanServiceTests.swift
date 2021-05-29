import Foundation
import TuistCoreTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CleanServiceTests: TuistUnitTestCase {
    var subject: CleanService!
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
        super.tearDown()
        subject = nil
    }

    func test_run_() throws {
        // Given
        let cachePath = try createFolders(["Cache"]).first!
        let correctlyCreated = FileManager.default.fileExists(atPath: cachePath.pathString)
        XCTAssertTrue(correctlyCreated, "Test setup is not properly done. Folder \(cachePath.pathString) should exist")
        cacheDirectoriesProvider.cacheDirectoryStub = cachePath

        // When
        try subject.run()

        // Then
        let expectedFalse = FileManager.default.fileExists(atPath: cachePath.pathString)
        XCTAssertFalse(expectedFalse, "Cache folder at path \(cachePath.pathString) should have been deleted by the test.")
    }
}
