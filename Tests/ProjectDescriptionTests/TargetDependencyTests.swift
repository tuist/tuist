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
        let subject = TargetDependency.library(
            path: "/path/library.a",
            publicHeaders: "/path/headers",
            swiftModuleMap: "/path/modulemap"
        )
        XCTAssertCodable(subject)
    }

    func test_sdk_codable() throws {
        // Given
        let sdks: [TargetDependency] = [
            .sdk(name: "A", type: .framework),
            .sdk(name: "B", type: .framework, status: .required),
            .sdk(name: "c", type: .framework, status: .optional),
        ]

        // When
        let encoded = try JSONEncoder().encode(sdks)
        let decoded = try JSONDecoder().decode([TargetDependency].self, from: encoded)

        // Then
        XCTAssertEqual(decoded, sdks)
    }

    func test_xcframework_codable() {
        // Given
        let subject: [TargetDependency] = [
            .xcframework(path: "/path/framework.xcframework"),
        ]

        // Then
        XCTAssertCodable(subject)
    }

    func test_instanceTarget() {
        let target = Target(name: "Target", platform: .iOS, product: .framework, bundleId: "bundleId")
        let subject = TargetDependency.target(target)
        XCTAssertEqual(subject, TargetDependency.target(name: "Target"))
    }
}
