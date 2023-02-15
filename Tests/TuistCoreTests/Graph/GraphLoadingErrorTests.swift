import Foundation
import TSCBasic
import XCTest
@testable import TuistCore

final class GraphLoadingErrorTests: XCTestCase {
    func test_description_returns_the_right_value_when_manifestNotFound() throws {
        let path = try AbsolutePath(validating: "/test/Project.swift")
        XCTAssertEqual(
            GraphLoadingError.manifestNotFound(path).description,
            "Couldn't find manifest at path: '/test/Project.swift'"
        )
    }

    func test_description_returns_the_right_value_when_targetNotFound() throws {
        let path = try AbsolutePath(validating: "/test/Project.swift")
        XCTAssertEqual(
            GraphLoadingError.targetNotFound("Target", path).description,
            "Couldn't find target 'Target' at '/test/Project.swift'"
        )
    }

    func test_description_returns_the_right_value_when_missingFile() throws {
        let path = try AbsolutePath(validating: "/path/file.swift")
        XCTAssertEqual(GraphLoadingError.missingFile(path).description, "Couldn't find file at path '/path/file.swift'")
    }

    func test_description_returns_the_right_value_when_unexpected() {
        XCTAssertEqual(GraphLoadingError.unexpected("message").description, "message")
    }

    func test_description_returns_the_right_value_when_circularDependency() throws {
        let from = GraphCircularDetectorNode(path: try AbsolutePath(validating: "/from"), name: "FromTarget")
        let to = GraphCircularDetectorNode(path: try AbsolutePath(validating: "/to"), name: "ToTarget")
        let error = GraphLoadingError.circularDependency([from, to])
        XCTAssertEqual(error.description, """
        Found circular dependency between targets: /from:FromTarget -> /to:ToTarget
        """)
    }
}
