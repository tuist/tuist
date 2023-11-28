import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class TargetDependencyTests: TuistUnitTestCase {
    func test_codable_framework() {
        // Given
        let subject = TargetDependency.framework(
            path: "/path/to/framework",
            status: .required
        )

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

    func test_filtering() {
        let expected: TargetDependency.Condition? = .when([.macos])

        let subjects: [TargetDependency] = [
            .framework(path: "/", status: .required, condition: expected),
            .library(path: "/", publicHeaders: "/", swiftModuleMap: "/", condition: expected),
            .sdk(name: "", status: .required, condition: expected),
            .package(product: "", type: .plugin, condition: expected),
            .target(name: "", condition: expected),
            .xcframework(path: "/", status: .required, condition: expected),
            .project(target: "", path: "/", condition: expected),
        ]

        for subject in subjects {
            XCTAssertEqual(subject.condition, expected)
            XCTAssertEqual(subject.withCondition(.when([.catalyst])).condition, .when([.catalyst]))
        }
    }

    func test_xctest_platformFilters_alwaysReturnAll() {
        let subject = TargetDependency.xctest

        XCTAssertNil(subject.condition)
        XCTAssertNil(subject.withCondition(.when([.catalyst])).condition)
    }
}
