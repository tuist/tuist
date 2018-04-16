import Foundation
@testable import ProjectDescription
import XCTest

final class BuildFilesTests: XCTestCase {
    func test_toJSON_returns_the_right_value_when_include() {
        let subject = BuildFiles.include(["/path"])
        let json = subject.toJSON()
        let expected = """
        {"paths": ["/path"], "type": "include"}
        """
        XCTAssertEqual(json.toString(), expected)
    }

    func test_toJSON_returns_the_right_value_when_exclude() {
        let subject = BuildFiles.exclude(["/path"])
        let json = subject.toJSON()
        let expected = """
        {"paths": ["/path"], "type": "exclude"}
        """
        XCTAssertEqual(json.toString(), expected)
    }
}
