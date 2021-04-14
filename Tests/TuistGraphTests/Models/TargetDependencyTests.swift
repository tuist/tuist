import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class TargetDependencyTests: TuistUnitTestCase {
    func test_codable_framework() {
        // Given
        let subject = TargetDependency.framework(path: "/path/to/framework")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_project() {
        // Given
        let subject = TargetDependency.project(target: "target", path: "/path/to/target")

        // Then
        XCTAssertCodable(subject)
    }
}
