import Foundation
import Path
import TuistCore
import TuistMigration
import TuistSupport
import Testing
@testable import TuistKit
@testable import TuistTesting

struct MigrationCheckEmptyBuildSettingsServiceTests {
    var subject: MigrationCheckEmptyBuildSettingsService!
    var emptyBuildSettingsChecker: MockEmptyBuildSettingsChecker!

    init() {
        emptyBuildSettingsChecker = MockEmptyBuildSettingsChecker()
        subject = MigrationCheckEmptyBuildSettingsService(emptyBuildSettingsChecker: emptyBuildSettingsChecker)
    }

    @Test func test_run() async throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/test.xcodeproj")
        let target = "test"

        // When
        try await subject.run(xcodeprojPath: xcodeprojPath, target: target)

        // Then
        #expect(emptyBuildSettingsChecker.invokedCheckParameters?.xcodeprojPath == xcodeprojPath)
        #expect(emptyBuildSettingsChecker.invokedCheckParameters?.targetName == target)
    }

    @Test func test_run_rethrows_errors_thrown_by_the_checker() async throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/test.xcodeproj")
        let target = "test"
        let error = TestError("error")
        emptyBuildSettingsChecker.stubbedCheckError = error

        // When
        await XCTAssertThrowsSpecific(try await subject.run(xcodeprojPath: xcodeprojPath, target: target), error)
    }
}
