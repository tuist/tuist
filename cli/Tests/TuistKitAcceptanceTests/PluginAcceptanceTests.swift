import FileSystemTesting
import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct PluginAcceptanceTests {
    @Test(.withFixture("generated_tuist_plugin"))
    func tuist_plugin() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(PluginBuildCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(PluginRunCommand.self, ["tuist-create-file", "--path", fixtureDirectory.pathString])
    }

    @Test(.withFixture("generated_app_with_plugins"), .inTemporaryDirectory)
    func app_with_plugins() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
    }
}
