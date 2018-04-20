import Basic
import Foundation
@testable import xcbuddykit
import XCTest

final class GraphLoadingErrorTests: XCTestCase {
    func test_description_returns_the_right_value_when_manifestNotFound() {
        let path = AbsolutePath("/test/Project.swift")
        XCTAssertEqual(GraphLoadingError.manifestNotFound(path).description, "Couldn't find manifest at path: '/test/Project.swift'")
    }

    func test_description_returns_the_right_value_when_targetNotFound() {
        let path = AbsolutePath("/test/Project.swift")
        XCTAssertEqual(GraphLoadingError.targetNotFound("Target", path).description, "Couldn't find target 'Target' at '/test/Project.swift'")
    }

    func test_description_returns_the_right_value_when_missingFile() {
        let path = AbsolutePath("/path/file.swift")
        XCTAssertEqual(GraphLoadingError.missingFile(path).description, "Couldn't find file at path '/path/file.swift'")
    }

    func test_description_returns_the_right_value_when_unexpected() {
        XCTAssertEqual(GraphLoadingError.unexpected("message").description, "message")
    }
}
