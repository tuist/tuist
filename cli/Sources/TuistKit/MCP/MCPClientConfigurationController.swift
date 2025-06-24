import FileSystem
import Mockable
import Path
import SwiftyJSON

enum MCPClientType {
    case claude
    case claudeCode
    case cursor
    case zed
    case vscode
}

@Mockable
protocol MCPClientConfigurationControlling {
    func update(for client: MCPClientType, at configPath: AbsolutePath) async throws
}

struct MCPClientConfigurationController: MCPClientConfigurationControlling {
    private let fileSystem: FileSystem
    private let serverCommandResolver: MCPServerCommandResolving

    init() {
        self.init(fileSystem: FileSystem(), serverCommandResolver: MCPServerCommandResolver())
    }

    init(fileSystem: FileSystem, serverCommandResolver: MCPServerCommandResolving) {
        self.fileSystem = fileSystem
        self.serverCommandResolver = serverCommandResolver
    }

    func update(for client: MCPClientType, at configPath: AbsolutePath) async throws {
        if !(try await fileSystem.exists(configPath.parentDirectory, isDirectory: true)) {
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        }

        let (command, args) = serverCommandResolver.resolve()

        switch client {
        case .claude, .claudeCode:
            try await updateClaudeConfig(at: configPath, command: command, args: args)
        case .cursor:
            try await updateCursorConfig(at: configPath, command: command, args: args)
        case .zed:
            try await updateZedConfig(at: configPath, command: command, args: args)
        case .vscode:
            try await updateVSCodeConfig(at: configPath, command: command, args: args)
        }
    }

    private func updateClaudeConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var mcpJSON: JSON = if try await fileSystem.exists(configPath) {
            JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        } else {
            [:]
        }

        if !mcpJSON["mcpServers"].exists() {
            mcpJSON["mcpServers"] = [:]
        }
        mcpJSON["mcpServers"]["tuist"] = ["command": command, "args": args]
        try mcpJSON.rawData().write(to: configPath.url, options: .atomic)
    }

    private func updateCursorConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var settingsJSON: JSON = if try await fileSystem.exists(configPath) {
            JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        } else {
            [:]
        }

        if !settingsJSON["mcp.servers"].exists() {
            settingsJSON["mcp.servers"] = [:]
        }
        settingsJSON["mcp.servers"]["tuist"] = [
            "command": command,
            "args": args
        ]
        try settingsJSON.rawData().write(to: configPath.url, options: .atomic)
    }

    private func updateZedConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var settingsJSON: JSON = if try await fileSystem.exists(configPath) {
            JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        } else {
            [:]
        }

        if !settingsJSON["mcp_servers"].exists() {
            settingsJSON["mcp_servers"] = [:]
        }
        settingsJSON["mcp_servers"]["tuist"] = [
            "command": command,
            "args": args
        ]
        try settingsJSON.rawData().write(to: configPath.url, options: .atomic)
    }

    private func updateVSCodeConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var settingsJSON: JSON = if try await fileSystem.exists(configPath) {
            JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        } else {
            [:]
        }

        if !settingsJSON["mcp.servers"].exists() {
            settingsJSON["mcp.servers"] = [:]
        }
        settingsJSON["mcp.servers"]["tuist"] = [
            "command": command,
            "args": args
        ]
        try settingsJSON.rawData().write(to: configPath.url, options: .atomic)
    }
}