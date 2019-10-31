import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class WorkspaceTests: XCTestCase {
    func test_toJSON() throws {
        let subject = Workspace(name: "name", projects: ["/path/to/project"])
        XCTAssertCodable(subject)
    }

    func test_toJSON_withAdditionalFiles() throws {
        let subject = Workspace(name: "name",
                                projects: ["ProjectA"],
                                additionalFiles: [
                                    .glob(pattern: "Documentation/**"),
                                ])
        XCTAssertCodable(subject)
    }
}
