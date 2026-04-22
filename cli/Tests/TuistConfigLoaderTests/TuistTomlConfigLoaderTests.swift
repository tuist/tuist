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

            [http]
            proxy = false
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
        #expect(config?.http?.proxy == false)
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
        #expect(config?.http == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_config_with_http_only() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            [http]
            proxy = false
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

        #expect(config?.project == nil)
        #expect(config?.url == nil)
        #expect(config?.http?.proxy == false)
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
