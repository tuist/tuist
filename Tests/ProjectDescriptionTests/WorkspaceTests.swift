import Foundation
@testable import ProjectDescription
import XCTest

final class WorkspaceTests: XCTestCase {
    func test_toJSON() {
        let subject = Workspace(name: "name", projects: ["/path/to/project"])
        let expected = "{\"name\": \"name\", \"projects\": [\"/path/to/project\"]}"
        assertCodableEqualToJson(subject, expected)
    }
}
