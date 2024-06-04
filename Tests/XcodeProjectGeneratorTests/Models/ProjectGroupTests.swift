import Foundation
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class ProjectGroupTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ProjectGroup.group(name: "name")

        // Then
        XCTAssertCodable(subject)
    }
}
