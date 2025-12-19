import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistTesting

@testable import TuistKit

struct MCPCodexConfigurationFileControllerTests {
    private let fileSystem = FileSystem()
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let subject: MCPCodexConfigurationFileControlling

    init() {
        subject = MCPCodexConfigurationFileController(
            fileSystem: fileSystem,
            serverCommandResolver: serverCommandResolver
        )
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory) func update_createsFile_when_itDoesntExist() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
        let configPath = temporaryDirectory.appending(components: [".codex", "config.toml"])

        // When
        try await subject.update(at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        #expect(content.contains("[mcp_servers.tuist]"))
        #expect(content.contains(#"command = "tuist""#))
        #expect(content.contains(#"args = ["mcp", "start"]"#))
    }

    @Test(
        .withMockedDependencies(),
        .inTemporaryDirectory
    ) func update_appendsConfiguration_when_fileExistsWithoutTuistServer() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
        let configPath = temporaryDirectory.appending(components: [".codex", "config.toml"])
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try Data(#"model = "o3""#.utf8).write(to: configPath.url, options: .atomic)

        // When
        try await subject.update(at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        #expect(content.contains(#"model = "o3""#))
        #expect(content.contains("[mcp_servers.tuist]"))
        #expect(content.contains(#"command = "tuist""#))
        #expect(content.contains(#"args = ["mcp", "start"]"#))
        #expect(content.components(separatedBy: "[mcp_servers.tuist]").count == 2)
    }

    @Test(
        .withMockedDependencies(),
        .inTemporaryDirectory
    ) func update_overridesExistingTuistServerConfiguration_when_itExists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
        let configPath = temporaryDirectory.appending(components: [".codex", "config.toml"])
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)

        let existingConfig = """
        [mcp_servers.tuist]
        command = "old"
        args = ["old"]
        enabled = false

        [mcp_servers.other]
        command = "other"
        args = ["x"]
        """
        try Data(existingConfig.utf8).write(to: configPath.url, options: .atomic)

        // When
        try await subject.update(at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        #expect(content.contains(#"command = "tuist""#))
        #expect(content.contains(#"args = ["mcp", "start"]"#))
        #expect(content.contains("enabled = false"))
        #expect(content.contains(#"[mcp_servers.other]"#))
        #expect(!content.contains(#"command = "old""#))
        #expect(!content.contains(#"args = ["old"]"#))
        #expect(content.components(separatedBy: "[mcp_servers.tuist]").count == 2)
    }
}

