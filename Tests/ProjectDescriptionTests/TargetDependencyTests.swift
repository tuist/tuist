import Foundation
@testable import ProjectDescription
import XCTest

final class TargetDependencyTests: XCTestCase {
    func test_toJSON_returns_the_right_value_when_target() {
        let subject = TargetDependency.target(name: "Target")
        let json = subject.toJSON()
        let expected = """
        {"name": "Target", "type": "target"}
        """
        XCTAssertEqual(json.toString(), expected)
    }

    func test_toJSON_returns_the_right_value_when_project() {
        let subject = TargetDependency.project(target: "target", path: "path")
        let json = subject.toJSON()
        let expected = "{\"path\": \"path\", \"target\": \"target\", \"type\": \"project\"}"
        XCTAssertEqual(json.toString(), expected)
    }

    func test_toJSON_returns_the_right_value_when_framework() {
        let subject = TargetDependency.framework(path: "/path/framework.framework")
        let json = subject.toJSON()
        let expected = """
        {"path": "/path/framework.framework", "type": "framework"}
        """
        XCTAssertEqual(json.toString(), expected)
    }

    func test_toJSON_returns_the_right_value_when_library() {
        let subject = TargetDependency.library(path: "/path/library.a", publicHeaders: "/path/headers", swiftModuleMap: "/path/modulemap")
        let json = subject.toJSON()
        let expected = """
        {"path": "/path/library.a", "public_headers": "/path/headers", "swift_module_map": "/path/modulemap", "type": "library"}
        """
        XCTAssertEqual(json.toString(), expected)
    }
}
