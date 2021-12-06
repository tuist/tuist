import Foundation
import TSCBasic
import XCTest
@testable import TuistCore

final class GraphLoadingErrorTests: XCTestCase {
    func test_description_returns_the_right_value_when_manifestNotFound() {
        let path = AbsolutePath("/test/Project.swift")
        XCTAssertEqual(
            GraphLoadingError.manifestNotFound(path).description,
            "Couldn't find manifest at path: '/test/Project.swift'"
        )
    }

    func test_description_returns_the_right_value_when_targetNotFound() {
        let path = AbsolutePath("/test/Project.swift")
        XCTAssertEqual(
            GraphLoadingError.targetNotFound("Target", path).description,
            "Couldn't find target 'Target' at '/test/Project.swift'"
        )
    }

    func test_description_returns_the_right_value_when_missingFile() {
        let path = AbsolutePath("/path/file.swift")
        XCTAssertEqual(GraphLoadingError.missingFile(path).description, "Couldn't find file at path '/path/file.swift'")
    }

    func test_description_returns_the_right_value_when_unexpected() {
        XCTAssertEqual(GraphLoadingError.unexpected("message").description, "message")
    }

    func test_description_returns_the_right_value_when_circularDependency() {
        let from = GraphCircularDetectorNode(path: AbsolutePath("/from"), name: "FromTarget")
        let to = GraphCircularDetectorNode(path: AbsolutePath("/to"), name: "ToTarget")
        let error = GraphLoadingError.circularDependency([from, to])
        XCTAssertEqual(error.description, """
        Found circular dependency between targets: /from:FromTarget -> /to:ToTarget
        """)
    }
}
