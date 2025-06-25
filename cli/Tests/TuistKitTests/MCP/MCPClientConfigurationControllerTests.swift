import FileSystem
import Foundation
import Mockable
import Path
import SwiftyJSON
import Testing
import TuistTesting

@testable import TuistKit

struct MCPClientConfigurationControllerTests {
    private let serverCommandResolver = MockMCPServerCommandResolving()
    private let subject: MCPClientConfigurationController

    init() throws {
        subject = MCPClientConfigurationController(
            fileSystem: FileSystem(),
            serverCommandResolver: serverCommandResolver
        )
    }

//    @Test func update_claude_creates_directory_if_missing() async throws {
//        try await withMockedDependencies {
//            // Given
//            let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
//            given(serverCommandResolver)
//                .resolve()
//                .willReturn(("/path/to/tuist", ["mcp", "start"]))
//            given(fileSystem)
//                .exists(configPath.parentDirectory, isDirectory: true)
//                .willReturn(false)
//            given(fileSystem)
//                .makeDirectory(at: configPath.parentDirectory)
//                .willReturn()
//            given(fileSystem)
//                .exists(configPath)
//                .willReturn(false)
//
//            // When
//            try await subject.update(for: .claude, at: configPath)
//
//            // Then
//            verify(fileSystem)
//                .makeDirectory(at: configPath.parentDirectory)
//                .called(1)
//        }
//    }
//
//    @Test func update_claude_creates_new_config_when_file_doesnt_exist() async throws {
//        try await withMockedDependencies {
//            // Given
//            let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
//            given(serverCommandResolver)
//                .resolve()
//                .willReturn(("/path/to/tuist", ["mcp", "start"]))
//            given(fileSystem)
//                .exists(configPath.parentDirectory, isDirectory: true)
//                .willReturn(true)
//            given(fileSystem)
//                .exists(configPath)
//                .willReturn(false)
//
//            var writtenData: Data?
//            given(fileSystem)
//                .writeFile(data: any(), to: configPath.url, options: any())
//                .willProduce { data, _, _ in
//                    writtenData = data
//                }
//
//            // When
//            try await subject.update(for: .claude, at: configPath)
//
//            // Then
//            let json = try JSON(data: writtenData!)
//            #expect(json["mcpServers"]["tuist"]["command"].stringValue == "/path/to/tuist")
//            #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
//        }
//    }
//
//    @Test func update_claude_merges_with_existing_config() async throws {
//        try await withMockedDependencies {
//            // Given
//            let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
//            let existingConfig = JSON([
//                "mcpServers": [
//                    "other": [
//                        "command": "/other/command",
//                        "args": ["arg1"]
//                    ]
//                ]
//            ])
//
//            given(serverCommandResolver)
//                .resolve()
//                .willReturn(("/path/to/tuist", ["mcp", "start"]))
//            given(fileSystem)
//                .exists(configPath.parentDirectory, isDirectory: true)
//                .willReturn(true)
//            given(fileSystem)
//                .exists(configPath)
//                .willReturn(true)
//            given(fileSystem)
//                .readTextFile(at: configPath)
//                .willReturn(existingConfig.rawString()!)
//
//            var writtenData: Data?
//            given(fileSystem)
//                .writeFile(data: any(), to: configPath.url, options: any())
//                .willProduce { data, _, _ in
//                    writtenData = data
//                }
//
//            // When
//            try await subject.update(for: .claude, at: configPath)
//
//            // Then
//            let json = try JSON(data: writtenData!)
//            #expect(json["mcpServers"]["other"]["command"].stringValue == "/other/command")
//            #expect(json["mcpServers"]["tuist"]["command"].stringValue == "/path/to/tuist")
//            #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
//        }
//    }
//
//    @Test func update_cursor_creates_correct_config_structure() async throws {
//        try await withMockedDependencies {
//            // Given
//            let configPath = temporaryDirectory.appending(component: "settings.json")
//            given(serverCommandResolver)
//                .resolve()
//                .willReturn(("/path/to/tuist", ["mcp", "start"]))
//            given(fileSystem)
//                .exists(configPath.parentDirectory, isDirectory: true)
//                .willReturn(true)
//            given(fileSystem)
//                .exists(configPath)
//                .willReturn(false)
//
//            var writtenData: Data?
//            given(fileSystem)
//                .writeFile(data: any(), to: configPath.url, options: any())
//                .willProduce { data, _, _ in
//                    writtenData = data
//                }
//
//            // When
//            try await subject.update(for: .cursor, at: configPath)
//
//            // Then
//            let json = try JSON(data: writtenData!)
//            #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "/path/to/tuist")
//            #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
//        }
//    }
//
//    @Test func update_zed_creates_correct_config_structure() async throws {
//        try await withMockedDependencies {
//            // Given
//            let configPath = temporaryDirectory.appending(component: "settings.json")
//            given(serverCommandResolver)
//                .resolve()
//                .willReturn(("/path/to/tuist", ["mcp", "start"]))
//            given(fileSystem)
//                .exists(configPath.parentDirectory, isDirectory: true)
//                .willReturn(true)
//            given(fileSystem)
//                .exists(configPath)
//                .willReturn(false)
//
//            var writtenData: Data?
//            given(fileSystem)
//                .writeFile(data: any(), to: configPath.url, options: any())
//                .willProduce { data, _, _ in
//                    writtenData = data
//                }
//
//            // When
//            try await subject.update(for: .zed, at: configPath)
//
//            // Then
//            let json = try JSON(data: writtenData!)
//            #expect(json["mcp_servers"]["tuist"]["command"].stringValue == "/path/to/tuist")
//            #expect(json["mcp_servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
//        }
//    }
//
//    @Test func update_vscode_creates_correct_config_structure() async throws {
//        try await withMockedDependencies {
//            // Given
//            let configPath = temporaryDirectory.appending(component: "settings.json")
//            given(serverCommandResolver)
//                .resolve()
//                .willReturn(("/path/to/tuist", ["mcp", "start"]))
//            given(fileSystem)
//                .exists(configPath.parentDirectory, isDirectory: true)
//                .willReturn(true)
//            given(fileSystem)
//                .exists(configPath)
//                .willReturn(false)
//
//            var writtenData: Data?
//            given(fileSystem)
//                .writeFile(data: any(), to: configPath.url, options: any())
//                .willProduce { data, _, _ in
//                    writtenData = data
//                }
//
//            // When
//            try await subject.update(for: .vscode, at: configPath)
//
//            // Then
//            let json = try JSON(data: writtenData!)
//            #expect(json["mcp.servers"]["tuist"]["command"].stringValue == "/path/to/tuist")
//            #expect(json["mcp.servers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
//        }
//    }
//
//    @Test func update_claude_code_creates_correct_config_structure() async throws {
//        try await withMockedDependencies {
//            // Given
//            let configPath = temporaryDirectory.appending(component: "claude_desktop_config.json")
//            given(serverCommandResolver)
//                .resolve()
//                .willReturn(("/path/to/tuist", ["mcp", "start"]))
//            given(fileSystem)
//                .exists(configPath.parentDirectory, isDirectory: true)
//                .willReturn(true)
//            given(fileSystem)
//                .exists(configPath)
//                .willReturn(false)
//
//            var writtenData: Data?
//            given(fileSystem)
//                .writeFile(data: any(), to: configPath.url, options: any())
//                .willProduce { data, _, _ in
//                    writtenData = data
//                }
//
//            // When
//            try await subject.update(for: .claudeCode, at: configPath)
//
//            // Then
//            let json = try JSON(data: writtenData!)
//            #expect(json["mcpServers"]["tuist"]["command"].stringValue == "/path/to/tuist")
//            #expect(json["mcpServers"]["tuist"]["args"].arrayValue.map(\.stringValue) == ["mcp", "start"])
//        }
//    }
}
