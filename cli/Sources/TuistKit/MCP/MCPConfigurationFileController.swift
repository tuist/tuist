import FileSystem
import Mockable
import Path
import SwiftyJSON

@Mockable
protocol MCPConfigurationFileControlling {
    func update(at configPath: AbsolutePath) async throws
}

struct MCPConfigurationFileController: MCPConfigurationFileControlling {
    private let fileSystem: FileSystem
    private let serverCommandResolver: MCPServerCommandResolving

    init() {
        self.init(fileSystem: FileSystem(), serverCommandResolver: MCPServerCommandResolver())
    }

    init(fileSystem: FileSystem, serverCommandResolver: MCPServerCommandResolving) {
        self.fileSystem = fileSystem
        self.serverCommandResolver = serverCommandResolver
    }

    func update(at configPath: AbsolutePath) async throws {
        if !(try await fileSystem.exists(configPath.parentDirectory, isDirectory: true)) {
            try await fileSystem.makeDirectory(at: configPath.parentDirectory)
        }

        var mcpJSON = if try await !fileSystem.exists(configPath) {
            JSON()
        } else {
            JSON(parseJSON: try await fileSystem.readTextFile(at: configPath))
        }

        let (command, args) = serverCommandResolver.resolve()
        if !mcpJSON["mcpServers"].exists() {
            mcpJSON["mcpServers"] = [:]
        }
        mcpJSON["mcpServers"]["tuist"] = ["command": command, "args": args]
        try mcpJSON.rawData().write(to: configPath.url, options: .atomic)
    }
}
