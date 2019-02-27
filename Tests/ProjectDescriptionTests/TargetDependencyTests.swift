import Foundation
import XCTest
@testable import ProjectDescription

final class TargetDependencyTests: XCTestCase {
    func test_toJSON_when_target() {
        let subject = TargetDependency.target(name: "Target")
        let expected = """
        {"name": "Target", "type": "target"}
        """
        assertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_when_project() {
        let subject = TargetDependency.project(target: "target", path: "path")
        let expected = "{\"path\": \"path\", \"target\": \"target\", \"type\": \"project\"}"
        assertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_when_framework() {
        let subject = TargetDependency.framework(path: "/path/framework.framework")
        let expected = """
        {"path": "/path/framework.framework", "type": "framework"}
        """
        assertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_when_library() {
        let subject = TargetDependency.library(path: "/path/library.a", publicHeaders: "/path/headers", swiftModuleMap: "/path/modulemap")
        let expected = """
        {"path": "/path/library.a", "public_headers": "/path/headers", "swift_module_map": "/path/modulemap", "type": "library"}
        """
        assertCodableEqualToJson(subject, expected)
    }
}
