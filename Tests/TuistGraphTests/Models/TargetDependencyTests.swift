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

    func test_codable_library() {
        // Given
        let subject = TargetDependency.library(
            path: "/path/to/library",
            publicHeaders: "/path/to/publicheaders",
            swiftModuleMap: "/path/to/swiftModuleMap"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
