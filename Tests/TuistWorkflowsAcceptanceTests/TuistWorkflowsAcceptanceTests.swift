import Command
import Path
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class WorkflowsAcceptanceTestsAppWithWorkflows: TuistAcceptanceTestCase {
    func test_runs_the_workflow() async throws {
        try await setUpFixture(.appWithWorkflows)
        try await run(WorkflowsRunCommand.self, "build")
        try await run(WorkflowsLSCommand.self, "--json")
        let expectedOutput = #"""
        [
          {
            "name" : "build",
            "package_swift_path" : "\/var\/folders\/f_\/c8lgm50920q1gx_bmk0s3gs80000gn\/T\/TemporaryDirectory.4lvCVX\/app_with_workflows\/Tuist\/Workflows\/Package.swift",
            "description" : "Builds the project"
          }
        ]
        """#
        XCTAssertStandardOutput(pattern: expectedOutput)
    }
}
