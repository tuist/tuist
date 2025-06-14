import TuistAcceptanceTesting
import TuistSupport
import TuistTesting
import XcodeProj
import XCTest

final class RunAcceptanceTestCommandLineToolBasic: TuistAcceptanceTestCase {
    func test_command_line_tool_basic() async throws {
        try await setUpFixture(.commandLineToolBasic)
        try await run(InstallCommand.self)
        try await run(RunCommand.self, "CommandLineTool")
    }
}
