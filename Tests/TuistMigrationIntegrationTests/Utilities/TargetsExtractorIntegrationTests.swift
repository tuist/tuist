import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistMigration
@testable import TuistSupportTesting

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

    func test_when_the_xcodeproj_path_doesnt_exist() throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/invalid/path.xcodeproj")

        // Then
        XCTAssertThrowsSpecific(
            try subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath),
            TargetsExtractorError.missingXcodeProj(xcodeprojPath)
        )
    }

    func test_when_existing_xcodeproj_path_with_targets() throws {
        // Given
        let xcodeprojPath = fixturePath(path: RelativePath("Frameworks/Frameworks.xcodeproj"))

        // Then
        let result = try subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)
        XCTAssertNotEmpty(result)
    }
}
