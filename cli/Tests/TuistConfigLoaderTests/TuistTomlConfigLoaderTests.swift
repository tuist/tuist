import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConstants
import TuistRootDirectoryLocator

@testable import TuistConfigLoader

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

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config?.project == "tuist/tuist")
        #expect(config?.url == URL(string: "https://custom.tuist.dev")!)
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

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config?.project == "org/project")
        #expect(config?.url == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_nil_when_no_root_directory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(nil as AbsolutePath?)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_nil_when_root_has_no_toml() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_parses_proxy_url_table() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            project = "tuist/tuist"

            [proxy]
            url = "http://proxy.corp:8080"
            """,
            at: tomlPath
        )

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config?.proxy?.url == URL(string: "http://proxy.corp:8080"))
        #expect(config?.proxy?.environmentVariable == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_parses_proxy_environment_variable_table() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            project = "tuist/tuist"

            [proxy]
            environment_variable = "HTTPS_PROXY"
            """,
            at: tomlPath
        )

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )
        let config = try await subject.loadConfig(at: temporaryDirectory)

        #expect(config?.proxy?.url == nil)
        #expect(config?.proxy?.environmentVariable == "HTTPS_PROXY")
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_proxy_rejects_both_url_and_environment_variable() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            project = "tuist/tuist"

            [proxy]
            url = "http://proxy.corp:8080"
            environment_variable = "HTTPS_PROXY"
            """,
            at: tomlPath
        )

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )

        await #expect(throws: (any Error).self) {
            _ = try await subject.loadConfig(at: temporaryDirectory)
        }
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_finds_toml_at_root_directory() async throws {
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

        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)

        let subject = TuistTomlConfigLoader(
            fileSystem: fileSystem,
            rootDirectoryLocator: rootDirectoryLocator
        )
        let config = try await subject.loadConfig(at: nestedDir)

        #expect(config?.project == "parent/project")
    }
}
