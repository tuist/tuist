import FileSystem
import Foundation
import Mockable
import Path
import SwiftyJSON
import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct MCPSetupVSCodeCommandServiceTests {
    private let fileSystem = FileSystem()
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let configurationFileController: MCPClientConfigurationControlling
    private let subject: MCPSetupVSCodeCommandService

    init() {
        configurationFileController = MCPClientConfigurationController(
            fileSystem: fileSystem,
            serverCommandResolver: serverCommandResolver
        )
        subject = MCPSetupVSCodeCommandService(
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
                ".vscode",
                "settings.json",
            ])
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
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
            let configPath = customPath.appending(components: [".vscode", "settings.json"])
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
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
            #if os(macOS)
                let vscodeConfigDir = mockedEnvironment.homeDirectory.appending(components: [
                    "Library",
                    "Application Support",
                    "Code",
                    "User",
                ])
            #elseif os(Linux)
                let vscodeConfigDir = mockedEnvironment.homeDirectory.appending(components: [".config", "Code", "User"])
            #else
                let vscodeConfigDir = mockedEnvironment.homeDirectory.appending(components: [
                    "AppData",
                    "Roaming",
                    "Code",
                    "User",
                ])
            #endif

            let configPath = vscodeConfigDir.appending(component: "settings.json")
            let exists = try await fileSystem.exists(configPath)
            #expect(exists)

            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func run_mergesWithExistingConfiguration() async throws {
        try await withMockedDependencies {
            // Given
            given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp", "start"]))
            let mockedEnvironment = try #require(Environment.mocked)

            // Create existing configuration
            let vscodeDir = try await mockedEnvironment.currentWorkingDirectory().appending(component: ".vscode")
            try await fileSystem.makeDirectory(at: vscodeDir)
            let configPath = vscodeDir.appending(component: "settings.json")

            let existingConfig: JSON = [
                "editor.fontSize": 14,
                "mcp.servers": [
                    "other": ["command": "other-server"],
                ],
            ]
            try existingConfig.rawData().write(to: configPath.url, options: .atomic)

            // When
            try await subject.run()

            // Then
            let content = try await fileSystem.readTextFile(at: configPath)
            let json = JSON(parseJSON: content)
            #expect(json["editor.fontSize"].intValue == 14)
            #expect(json["mcp.servers"]["other"]["command"].stringValue == "other-server")
            #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "tuist")
            #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
        }
    }
}
