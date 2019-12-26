import Foundation
import XCTest
@testable import ProjectDescription

final class TargetDependencyTests: XCTestCase {
    func test_toJSON_when_target() {
        let subject = TargetDependency.target(name: "Target")
        XCTAssertCodable(subject)
    }

    func test_toJSON_when_project() {
        let subject = TargetDependency.project(target: "target", path: "path")
        XCTAssertCodable(subject)
    }

    func test_toJSON_when_framework() {
        let subject = TargetDependency.framework(path: "/path/framework.framework")
        XCTAssertCodable(subject)
    }

    func test_toJSON_when_library() {
        let subject = TargetDependency.library(path: "/path/library.a", publicHeaders: "/path/headers", swiftModuleMap: "/path/modulemap")
        XCTAssertCodable(subject)
    }

    func test_sdk_codable() throws {
        // Given
        let sdks: [TargetDependency] = [
            .sdk(name: "A.framework"),
            .sdk(name: "B.framework", status: .required),
            .sdk(name: "c.framework", status: .optional),
        ]

        // When
        let encoded = try JSONEncoder().encode(sdks)
        let decoded = try JSONDecoder().decode([TargetDependency].self, from: encoded)

        // Then
        XCTAssertEqual(decoded, sdks)
    }

    func test_cocoapods_codable() throws {
        // Given
        let subject = TargetDependency.cocoapods(path: "./path")

        // Then
        XCTAssertCodable(subject)
    }

    func test_package_codable() throws {
        // Given
        let subject = TargetDependency.package(product: "foo")

        // Then
        XCTAssertCodable(subject)
    }

    func test_xcframework_codable() {
        // Given
        let subject = TargetDependency.xcFramework(path: "/path/framework.xcframework")

        // Then
        XCTAssertCodable(subject)
    }
}
