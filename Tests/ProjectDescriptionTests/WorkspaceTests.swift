import Foundation
@testable import ProjectDescription
import XCTest

final class WorkspaceTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
        let subject = Workspace(name: "name", projects: ["/path/to/project"])
        let json = subject.toJSON()
        let expected = "{\"name\": \"name\", \"project\": [\"/path/to/project\"]}"
        XCTAssertEqual(json.toString(), expected)
    }
}
