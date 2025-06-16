import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class WorkspaceTests: XCTestCase {
    func test_codable() throws {
        let subject = Workspace(name: "name", projects: ["/path/to/project"])
        XCTAssertCodable(subject)
    }

    func test_codable_withAdditionalFiles() throws {
        let subject = Workspace(
            name: "name",
            projects: ["ProjectA"],
            additionalFiles: [
                .glob(pattern: "Documentation/**"),
            ]
        )
        XCTAssertCodable(subject)
    }

    func test_codable_withGenerationOptions() throws {
        let subject = Workspace(
            name: "name",
            projects: ["ProjectA"],
            generationOptions: .options(enableAutomaticXcodeSchemes: true)
        )

        XCTAssertCodable(subject)
    }
}
