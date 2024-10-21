import Foundation
import Path
import TuistCore
import TuistSupport
import XCTest
@testable import TuistKit
@testable import TuistMigrationTesting
@testable import TuistSupportTesting

final class MigrationCheckEmptyBuildSettingsServiceTests: TuistUnitTestCase {
    var subject: MigrationCheckEmptyBuildSettingsService!
    var emptyBuildSettingsChecker: MockEmptyBuildSettingsChecker!

    override func setUp() {
        super.setUp()
        emptyBuildSettingsChecker = MockEmptyBuildSettingsChecker()
        subject = MigrationCheckEmptyBuildSettingsService(emptyBuildSettingsChecker: emptyBuildSettingsChecker)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_run() async throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/test.xcodeproj")
        let target = "test"

        // When
        try await subject.run(xcodeprojPath: xcodeprojPath, target: target)

        // Then
        XCTAssertEqual(emptyBuildSettingsChecker.invokedCheckParameters?.xcodeprojPath, xcodeprojPath)
        XCTAssertEqual(emptyBuildSettingsChecker.invokedCheckParameters?.targetName, target)
    }

    func test_run_rethrows_errors_thrown_by_the_checker() async throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/test.xcodeproj")
        let target = "test"
        let error = TestError("error")
        emptyBuildSettingsChecker.stubbedCheckError = error

        // When
        await XCTAssertThrowsSpecific(try await subject.run(xcodeprojPath: xcodeprojPath, target: target), error)
    }
}
