import Foundation
import Path
import TuistSupport
import XCTest

@testable import TuistMigration
@testable import TuistTesting

final class TargetsExtractorIntegrationTests: TuistTestCase {
    var subject: TargetsExtractor!

    override func setUp() {
        super.setUp()
        subject = TargetsExtractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_when_the_xcodeproj_path_doesnt_exist() async throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/invalid/path.xcodeproj")

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath),
            TargetsExtractorError.missingXcodeProj(xcodeprojPath)
        )
    }

    func test_when_existing_xcodeproj_path_with_targets() async throws {
        // Given
        let xcodeprojPath = fixturePath(path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj"))

        // Then
        let result = try await subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)
        XCTAssertNotEmpty(result)
    }
}
