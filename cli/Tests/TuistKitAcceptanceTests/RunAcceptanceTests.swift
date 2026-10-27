import Testing
import TuistRunCommand
import TuistSupport
import TuistTesting

@testable import TuistKit

struct RunAcceptanceTests {
    @Test(.withFixture("generated_command_line_tool_basic"))
    func command_line_tool_basic() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fixturePath = normalizedFixturePath(fixtureDirectory.pathString)
        try await TuistTest.run(InstallCommand.self, ["--path", fixturePath])
        try await TuistTest.run(
            RunCommand.self,
            ["--path", fixturePath, "CommandLineTool"]
        )
    }

    private func normalizedFixturePath(_ path: String) -> String {
        if path.hasPrefix("/private/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
