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

            [network]
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
        #expect(config?.network?.proxy == false)
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
        #expect(config?.network == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_config_with_network_only() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            [network]
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
        #expect(config?.network?.proxy == false)
        #expect(config?.testInsights == nil)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_config_with_coverage_upload() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            project = "acme/app"

            [test_insights.coverage]
            upload = true
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

        #expect(config?.testInsights?.coverage?.upload == true)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_config_with_network_ca_certificate() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlPath = temporaryDirectory.appending(component: Constants.tuistTomlFileName)
        try await fileSystem.writeText(
            """
            [network]
            proxy = true
            ca_certificate = "/etc/ssl/certs/ca.pem"
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

        #expect(config?.network?.proxy == true)
        #expect(config?.network?.caCertificate == "/etc/ssl/certs/ca.pem")
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

    @Test(.inTemporaryDirectory)
    func loadCargoManifestConfig_reads_the_workspace_root_from_a_member() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let source = root.appending(try RelativePath(validating: "crates/cli/src"))
        try await fileSystem.makeDirectory(at: source)
        try await fileSystem.writeText(
            """
            [workspace]
            members = ["crates/*"]
            resolver = "2"

            [workspace.dependencies]
            serde = { version = "1", features = ["derive"] }

            [workspace.metadata.tuist]
            project = "org/workspace"
            url = "https://custom.tuist.dev"

            [workspace.metadata.tuist.test_insights.coverage]
            upload = true

            [profile.dev]
            debug = "line-tables-only"
            """,
            at: root.appending(component: "Cargo.toml")
        )
        try await fileSystem.writeText(
            """
            [package]
            name = "cli"
            version = "0.1.0"

            [package.metadata.tuist]
            project = "org/member"
            """,
            at: root.appending(try RelativePath(validating: "crates/cli/Cargo.toml"))
        )

        let config = try await TuistTomlConfigLoader(fileSystem: fileSystem).loadCargoManifestConfig(at: source)

        #expect(config?.project == "org/workspace")
        #expect(config?.url == URL(string: "https://custom.tuist.dev")!)
        #expect(config?.testInsights?.coverage?.upload == true)
    }

    @Test(.inTemporaryDirectory)
    func loadCargoManifestConfig_reads_a_package_without_a_workspace() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.writeText(
            """
            [package]
            name = "tool"
            version = "0.1.0"

            [package.metadata.tuist]
            project = "org/tool"
            """,
            at: root.appending(component: "Cargo.toml")
        )

        let config = try await TuistTomlConfigLoader(fileSystem: fileSystem).loadCargoManifestConfig(at: root)

        #expect(config?.project == "org/tool")
    }
}
