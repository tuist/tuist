import Foundation
import XCTest
@testable import ProjectDescription

final class WorkspaceTests: XCTestCase {
    func test_toJSON() throws {
        let subject = Workspace(name: "name", projects: ["/path/to/project"])
        let expected = "{\"name\": \"name\", \"projects\": [\"/path/to/project\"]}"
        assertCodableEqualToJson(subject, expected)
    }
}
