import FileSystem
import Foundation
import Mockable
import SwiftyJSON
import Testing
import TuistTesting

@testable import TuistKit

struct MCPConfigurationFileControllerTests {
    private let fileSystem = FileSystem()
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let subject: MCPConfigurationFileControlling

    init() {
        subject = MCPConfigurationFileController(fileSystem: fileSystem, serverCommandResolver: serverCommandResolver)
    }

    @Test(.withMockedDependencies(), .inTemporaryDirectory) func update_createsTheFile_when_itDoesntExist() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp"]))
        let configPath = temporaryDirectory.appending(components: [".cursor", "mcp.json"])

        // When
        try await subject.update(at: configPath)

        // Then
        let cursorConfig = JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        #expect(cursorConfig["mcpServers"]["tuist"]["command"].stringValue == "tuist")
        #expect(cursorConfig["mcpServers"]["tuist"]["args"].arrayValue == ["mcp"])
    }

    @Test(
        .withMockedDependencies(),
        .inTemporaryDirectory
    ) func update_modifiesAnExistingConfiguration_when_itExists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp"]))
        let existingCursorConfiguration: JSON = ["mcpServers": [:]]
        let configPath = temporaryDirectory.appending(components: [".cursor", "mcp.json"])
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try existingCursorConfiguration.rawData().write(to: configPath.url, options: .atomic)

        // When
        try await subject.update(at: configPath)

        // Then
        let cursorConfig = JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        #expect(cursorConfig["mcpServers"]["tuist"]["command"].stringValue == "tuist")
        #expect(cursorConfig["mcpServers"]["tuist"]["args"].arrayValue == ["mcp"])
    }

    @Test(
        .withMockedDependencies(),
        .inTemporaryDirectory
    ) func update_overridesAnExistingTuistServerConfiguration_when_itExists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(serverCommandResolver).resolve().willReturn(("tuist", ["mcp"]))
        let existingCursorConfiguration: JSON = ["mcpServers": ["tuist": ["command": "old-tuist-command"]]]
        let configPath = temporaryDirectory.appending(components: [".cursor", "mcp.json"])
        try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        try existingCursorConfiguration.rawData().write(to: configPath.url, options: .atomic)

        // When
        try await subject.update(at: configPath)

        // Then
        let cursorConfig = JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        #expect(cursorConfig["mcpServers"]["tuist"]["command"].stringValue == "tuist")
        #expect(cursorConfig["mcpServers"]["tuist"]["args"].arrayValue == ["mcp"])
    }
}
