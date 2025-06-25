import FileSystem
import Foundation
import Mockable
import Path
import SwiftyJSON
import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct MCPSetupZedCommandServiceTests {
    private let fileSystem = FileSystem()
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let configurationFileController: MCPClientConfigurationControlling
    private let subject: MCPSetupZedCommandService

    init() {
        configurationFileController = MCPClientConfigurationController(
            fileSystem: fileSystem,
            serverCommandResolver: serverCommandResolver
        )
        subject = MCPSetupZedCommandService(
            fileSystem: fileSystem,
            configurationFileController: configurationFileController
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_createsLocalConfiguration_whenNoFlagsProvided() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let mockedEnvironment = try #require(Environment.mocked)

            // When
            try await subject.run()

            // Then
            let configPath = try await mockedEnvironment.currentWorkingDirectory().appending(components: [
                ".zed",
                "settings.json",
            ])
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcp_servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp_servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func run_createsConfigurationInSpecifiedPath_whenPathProvided() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let customPath = try await FileSystem.temporaryTestDirectory!.appending(component: "custom")
            try await fileSystem.makeDirectory(at: customPath)

            // When
            try await subject.run(path: customPath.pathString)

            // Then
            let configPath = customPath.appending(components: [".zed", "settings.json"])
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcp_servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp_servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func run_createsGlobalConfiguration_whenGlobalFlagProvided() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let mockedEnvironment = try #require(Environment.mocked)

            // When
            try await subject.run(global: true)

            // Then
            let configPath = mockedEnvironment.homeDirectory.appending(components: [".config", "zed", "settings.json"])
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcp_servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp_servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_mergesWithExistingConfiguration() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let mockedEnvironment = try #require(Environment.mocked)

            // Create existing configuration
            let zedDir = try await mockedEnvironment.currentWorkingDirectory().appending(component: ".zed")
            try await fileSystem.makeDirectory(at: zedDir)
            let configPath = zedDir.appending(component: "settings.json")

            let existingConfig: JSON = [
                "theme": "dark",
                "mcp_servers": [
                    "other": ["command": "other-server"],
                ],
            ]
            try existingConfig.rawData().write(to: configPath.url, options: .atomic)

            // When
            try await subject.run()

            // Then
            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["theme"].stringValue == "dark")
            #expect(json["mcp_servers"]["other"]["command"].stringValue == "other-server")
            #expect(json["mcp_servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp_servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }
}
