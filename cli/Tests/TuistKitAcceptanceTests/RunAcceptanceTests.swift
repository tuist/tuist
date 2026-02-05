import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct RunAcceptanceTests {
    @Test(.withFixture("generated_command_line_tool_basic"))
    func command_line_tool_basic() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(RunCommand.self, ["CommandLineTool", "--path", fixtureDirectory.pathString])
    }
}
