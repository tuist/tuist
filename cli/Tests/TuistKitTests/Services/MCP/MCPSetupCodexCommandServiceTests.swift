import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct MCPSetupCodexCommandServiceTests {
    private let fileSystem = FileSystem()
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let configurationFileController: MCPCodexConfigurationFileControlling
    private let subject: MCPSetupCodexCommandService

    init() {
        configurationFileController = MCPCodexConfigurationFileController(
            fileSystem: fileSystem,
            serverCommandResolver: serverCommandResolver
        )
        subject = MCPSetupCodexCommandService(
            fileSystem: fileSystem,
            configurationFileController: configurationFileController
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_createsConfigurationAtDefaultLocation_whenNoPathProvided() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let mockedEnvironment = try #require(Environment.mocked)

            // When
            try await subject.run()

            // Then
            let configPath = mockedEnvironment.homeDirectory.appending(components: [".codex", "config.toml"])
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            #expect(content.contains("[mcp_servers.tuist]"))
            #expect(content.contains(#"command = "tuist""#))
            #expect(content.contains(#"args = ["mcp", "start"]"#))
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_createsConfigurationInSpecifiedPath_whenPathProvided() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let customPath = try await FileSystem.temporaryTestDirectory!.appending(component: "custom-codex-home")
            try await fileSystem.makeDirectory(at: customPath)

            // When
            try await subject.run(path: customPath.pathString)

            // Then
            let configPath = customPath.appending(component: "config.toml")
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            #expect(content.contains("[mcp_servers.tuist]"))
            #expect(content.contains(#"command = "tuist""#))
            #expect(content.contains(#"args = ["mcp", "start"]"#))
        }
    }
}

