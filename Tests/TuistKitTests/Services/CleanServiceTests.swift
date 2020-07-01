import Foundation
import TuistSupport
import XCTest

@testable import TuistSupportTesting
@testable import TuistKit

final class CleanServiceTests: TuistUnitTestCase {
    var subject: CleanService!

    override func setUp() {
        super.setUp()
        
        let env = Environment.shared as! MockEnvironment
        env.cacheDirectoryStub = FileHandler.shared.currentPath.appending(component: "Cache")
        
        subject = CleanService()
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
        
        let env = Environment.shared as! MockEnvironment
        env.cacheDirectoryStub = cachePath

        // When
        try subject.run()
        
        // Then
        let expectedFalse = FileManager.default.fileExists(atPath: cachePath.pathString)
        XCTAssertFalse(expectedFalse, "Cache folder at path \(cachePath.pathString) should have been deleted by the test.")
    }
}
