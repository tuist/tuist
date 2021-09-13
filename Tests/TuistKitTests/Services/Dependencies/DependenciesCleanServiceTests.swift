import TSCBasic
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class DependenciesCleanServiceTests: TuistUnitTestCase {
    func test_run_whenDependenciesFolderExists_removesIt() throws {
        // Given
        let dependenciesPath = try createFolders(["Tuist/Dependencies"])[0]
        let stubbedPath = try temporaryPath()

        // When
        try DependenciesCleanService().run(path: stubbedPath.pathString)

        // Then
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dependenciesPath.pathString),
            "Cache folder at path \(dependenciesPath) should have been deleted by the test."
        )
    }

    func test_run_whenDependenciesFolderDoesNotExists_doesNothing() throws {
        // When
        try DependenciesCleanService().run(path: try temporaryPath().pathString)
    }
}
