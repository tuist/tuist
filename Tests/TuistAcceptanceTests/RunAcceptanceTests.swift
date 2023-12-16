import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class RunAcceptanceTestCommandLineToolBasic: TuistAcceptanceTestCase {
    func test_command_line_tool_basic() async throws {
        try setUpFixture("command_line_tool_basic")
        try await run(RunCommand.self, "CommandLineTool")
    }
}
