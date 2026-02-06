import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistConstants

@testable import TuistConfigToml

struct TuistTomlConfigLoaderTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_config_when_toml_exists() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            project = "tuist/tuist"
            url = "https://custom.tuist.dev"
            """,
            at: tomlPath
        )

        let subject = TuistTomlConfigLoader(fileSystem: fileSystem)
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config?.project == "tuist/tuist")
        #expect(config?.url == "https://custom.tuist.dev")
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_config_with_project_only() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            project = "org/project"
            """,
            at: tomlPath
        )

        let subject = TuistTomlConfigLoader(fileSystem: fileSystem)
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config?.project == "org/project")
        #expect(config?.url == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_nil_when_no_toml_exists() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let subject = TuistTomlConfigLoader(fileSystem: fileSystem)
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_finds_toml_in_parent_directory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let nestedDir = temporaryDirectory.appending(try RelativePath(validating: "nested/deep"))
        try await fileSystem.makeDirectory(at: nestedDir)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            project = "parent/project"
            """,
            at: tomlPath
        )

        let subject = TuistTomlConfigLoader(fileSystem: fileSystem)
        let config = try await subject.loadConfig(at: nestedDir)

        #expect(config?.project == "parent/project")
    }
}
