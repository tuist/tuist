import Foundation
import XCTest
@testable import XcodeGraph

final class ProjectGroupTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = ProjectGroup.group(name: "name")

        // Then
        XCTAssertCodable(subject)
    }
}
