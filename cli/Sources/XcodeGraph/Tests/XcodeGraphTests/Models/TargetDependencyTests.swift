import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class TargetDependencyTests: XCTestCase {
    func test_codable_framework() throws {
        // Given
        let subject = TargetDependency.framework(
            path: try AbsolutePath(validating: "/path/to/framework"),
            status: .required
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_project() throws {
        // Given
        let subject = TargetDependency.project(target: "target", path: try AbsolutePath(validating: "/path/to/target"))

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_library() throws {
        // Given
        let subject = TargetDependency.library(
            path: try AbsolutePath(validating: "/path/to/library"),
            publicHeaders: try AbsolutePath(validating: "/path/to/publicheaders"),
            swiftModuleMap: try AbsolutePath(validating: "/path/to/swiftModuleMap")
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_filtering() throws {
        let expected: PlatformCondition? = .when([.macos])

        let subjects: [TargetDependency] = [
            .framework(path: try AbsolutePath(validating: "/"), status: .required, condition: expected),
            .library(
                path: try AbsolutePath(validating: "/"),
                publicHeaders: try AbsolutePath(validating: "/"),
                swiftModuleMap: try AbsolutePath(validating: "/"),
                condition: expected
            ),
            .sdk(name: "", status: .required, condition: expected),
            .package(product: "", type: .plugin, condition: expected),
            .target(name: "", condition: expected),
            .xcframework(
                path: try AbsolutePath(validating: "/"),
                expectedSignature: nil,
                status: .required,
                condition: expected
            ),
            .project(target: "", path: try AbsolutePath(validating: "/"), condition: expected),
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
