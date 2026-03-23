import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct WorkspaceTests {
    @Test func test_codable() throws {
        let subject = Workspace(name: "name", projects: ["/path/to/project"])
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func test_codable_withAdditionalFiles() throws {
        let subject = Workspace(
            name: "name",
            projects: ["ProjectA"],
            additionalFiles: [
                .glob(pattern: "Documentation/**"),
            ]
        )
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func test_codable_withGenerationOptions() throws {
        let subject = Workspace(
            name: "name",
            projects: ["ProjectA"],
            generationOptions: .options(enableAutomaticXcodeSchemes: true)
        )

        #expect(try isCodableRoundTripable(subject))
    }
}
