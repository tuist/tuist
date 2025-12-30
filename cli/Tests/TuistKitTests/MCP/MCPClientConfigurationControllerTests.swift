import FileSystem
import Foundation
import Mockable
import Path
import SwiftyJSON
import Testing
import TuistTesting

@testable import TuistKit

struct MCPClientConfigurationControllerTests {
    private let fileSystem = FileSystem()
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let subject: MCPClientConfigurationController

    init() {
        subject = MCPClientConfigurationController(
            fileSystem: fileSystem,
            serverCommandResolver: serverCommandResolver
        )
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func update_claude_creates_directory_if_missing() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

        // When
        try await subject.update(for: .claude, at: configPath)

        // Then
        let parentExists = try await fileSystem.exists(configPath.parentDirectory, isDirectory: true)
        #expect(parentExists)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func update_claude_creates_new_config_when_file_doesnt_exist() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

        // When
        try await subject.update(for: .claude, at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        let json = JSON(parseJSON: content)
        #expect(json["mcpServers"]["tuist"]["command"].stringValue == "tuist")
        #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func update_claude_merges_with_existing_config() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
        let existingConfig: JSON = [
            "mcpServers": [
                "other": ["command": "other-server"],
            ],
        ]

        try existingConfig.rawData().write(to: configPath.url, options: .atomic)

        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

        // When
        try await subject.update(for: .claude, at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        let json = JSON(parseJSON: content)
        #expect(json["mcpServers"]["other"]["command"].stringValue == "other-server")
        #expect(json["mcpServers"]["tuist"]["command"].stringValue == "tuist")
        #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func update_cursor_creates_correct_config_structure() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryDirectory.appending(component: "settings.json")
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

        // When
        try await subject.update(for: .cursor, at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        let json = JSON(parseJSON: content)
        #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "tuist")
        #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func update_zed_creates_correct_config_structure() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryDirectory.appending(component: "settings.json")
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

        // When
        try await subject.update(for: .zed, at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        let json = JSON(parseJSON: content)
        #expect(json["mcp_servers"]["tuist"]["command"].stringValue == "tuist")
        #expect(json["mcp_servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func update_vscode_creates_correct_config_structure() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryDirectory.appending(component: "settings.json")
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

        // When
        try await subject.update(for: .vscode, at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        let json = JSON(parseJSON: content)
        #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "tuist")
        #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func update_claude_code_creates_correct_config_structure() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

        // When
        try await subject.update(for: .claudeCode, at: configPath)

        // Then
        let content = try await fileSystem.readTextFile(at: configPath)
        let json = JSON(parseJSON: content)
        #expect(json["mcpServers"]["tuist"]["command"].stringValue == "tuist")
        #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
    }
}
