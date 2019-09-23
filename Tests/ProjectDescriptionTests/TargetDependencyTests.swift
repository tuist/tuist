import Foundation
import XCTest
@testable import ProjectDescription

final class TargetDependencyTests: XCTestCase {
    func test_toJSON_when_target() {
        let subject = TargetDependency.target(name: "Target")
        let expected = """
        {"name": "Target", "type": "target"}
        """
        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_when_project() {
        let subject = TargetDependency.project(target: "target", path: "path")
        let expected = "{\"path\": \"path\", \"target\": \"target\", \"type\": \"project\"}"
        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_when_framework() {
        let subject = TargetDependency.framework(path: "/path/framework.framework")
        let expected = """
        {"path": "/path/framework.framework", "type": "framework"}
        """
        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_when_library() {
        let subject = TargetDependency.library(path: "/path/library.a", publicHeaders: "/path/headers", swiftModuleMap: "/path/modulemap")
        let expected = """
        {"path": "/path/library.a", "public_headers": "/path/headers", "swift_module_map": "/path/modulemap", "type": "library"}
        """
        XCTAssertCodableEqualToJson(subject, expected)
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

    func test_package_remotePackages_codable() throws {
        // Given
        let subject = TargetDependency.package(url: "https://github.com/Swinject/Swinject",
                                               productName: "Swinject",
                                               version: .upToNextMajor(from: "2.6.2"))

        // Then
        XCTAssertCodable(subject)
    }

    func test_package_localPackages_codable() throws {
        // Given
        let subject = TargetDependency.package(path: "foo/bar", productName: "FooBar")

        // Then
        XCTAssertCodable(subject)
    }
}
