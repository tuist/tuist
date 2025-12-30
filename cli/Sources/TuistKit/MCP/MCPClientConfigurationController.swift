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

    private func loadOrCreateJSON(at configPath: AbsolutePath) async throws -> JSON {
        if try await fileSystem.exists(configPath) {
            return JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        } else {
            return [:]
        }
    }

    private func ensureServersKeyExists(in json: inout JSON, keyPath: String) {
        if !json[keyPath].exists() {
            json[keyPath] = [:]
        }
    }

    private func setTuistServerConfig(in json: inout JSON, keyPath: String, command: String, args: [String]) {
        json[keyPath]["tuist"] = [
            "command": command,
            "args": args,
        ]
    }

    private func writeJSON(_ json: JSON, to configPath: AbsolutePath) throws {
        try json.rawData().write(to: configPath.url, options: .atomic)
    }

    private func updateClaudeConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var mcpJSON = try await loadOrCreateJSON(at: configPath)
        ensureServersKeyExists(in: &mcpJSON, keyPath: "mcpServers")
        setTuistServerConfig(in: &mcpJSON, keyPath: "mcpServers", command: command, args: args)
        try writeJSON(mcpJSON, to: configPath)
    }

    private func updateCursorConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var settingsJSON = try await loadOrCreateJSON(at: configPath)
        ensureServersKeyExists(in: &settingsJSON, keyPath: "mcp.servers")
        setTuistServerConfig(in: &settingsJSON, keyPath: "mcp.servers", command: command, args: args)
        try writeJSON(settingsJSON, to: configPath)
    }

    private func updateZedConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var settingsJSON = try await loadOrCreateJSON(at: configPath)
        ensureServersKeyExists(in: &settingsJSON, keyPath: "mcp_servers")
        setTuistServerConfig(in: &settingsJSON, keyPath: "mcp_servers", command: command, args: args)
        try writeJSON(settingsJSON, to: configPath)
    }

    private func updateVSCodeConfig(at configPath: AbsolutePath, command: String, args: [String]) async throws {
        var settingsJSON = try await loadOrCreateJSON(at: configPath)
        ensureServersKeyExists(in: &settingsJSON, keyPath: "mcp.servers")
        setTuistServerConfig(in: &settingsJSON, keyPath: "mcp.servers", command: command, args: args)
        try writeJSON(settingsJSON, to: configPath)
    }
}
