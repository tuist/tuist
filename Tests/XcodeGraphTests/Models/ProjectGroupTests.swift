import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class ProjectGroupTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ProjectGroup.group(name: "name")

        // Then
        XCTAssertCodable(subject)
    }
}
