import FileSystem
import Foundation
import Mockable
import Path
import SwiftyJSON
import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct MCPSetupClaudeCommandServiceTests {
    private let fileSystem = FileSystem()
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let configurationFileController: MCPClientConfigurationControlling
    private let subject: MCPSetupClaudeCommandService

    init() {
        configurationFileController = MCPClientConfigurationController(
            fileSystem: fileSystem,
            serverCommandResolver: serverCommandResolver
        )
        subject = MCPSetupClaudeCommandService(
            fileSystem: fileSystem,
            configurationFileController: configurationFileController
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_createsConfiguration() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let mockedEnvironment = try #require(Environment.mocked)

            // When
            try await subject.run()

            // Then
            let configPath = mockedEnvironment.homeDirectory.appending(components: [
                "Library",
                "Application Support",
                "Claude",
                "claude_desktop_config.json",
            ])
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcpServers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_mergesWithExistingConfiguration() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let mockedEnvironment = try #require(Environment.mocked)

            // Create existing configuration
            let claudeDir = mockedEnvironment.homeDirectory.appending(components: ["Library", "Application Support", "Claude"])
            try await fileSystem.makeDirectory(at: claudeDir)

            let configPath = claudeDir.appending(component: "claude_desktop_config.json")
            let existingConfig: JSON = [
                "mcpServers": [
                    "other": ["command": "other-server"],
                ],
            ]
            try existingConfig.rawData().write(to: configPath.url, options: .atomic)

            // When
            try await subject.run()

            // Then
            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcpServers"]["other"]["command"].stringValue == "other-server")
            #expect(json["mcpServers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_showsCorrectSuccessMessage() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))

            // When
            try await subject.run()

            // Then
            #expect(
                ui() == """
                ✔ Success
                  Claude configured to point to the Tuist's MCP server.

                  Takeaways:
                   ▸ Restart the Claude app if it was opened
                   ▸ Check out Claude's <documentation: https://modelcontextprotocol.io/quickstart/user>
                """
            )
        }
    }
}
