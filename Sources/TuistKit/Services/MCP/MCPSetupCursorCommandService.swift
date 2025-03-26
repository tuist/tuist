import FileSystem
import Foundation
import Path
import ServiceContextModule
import SwiftyJSON
import TuistSupport

struct MCPSetupCursorCommandService {
    private let fileSystem: FileSystem
    private let configurationFileController: MCPConfigurationFileControlling

    init(
        fileSystem: FileSystem = FileSystem(),
        configurationFileController: MCPConfigurationFileControlling = MCPConfigurationFileController()
    ) {
        self.fileSystem = fileSystem
        self.configurationFileController = configurationFileController
    }

    func run(directory: AbsolutePath) async throws {
        let mcpConfigPath = directory.appending(components: [".cursor", "mcp.json"])
        try await configurationFileController.update(at: mcpConfigPath)
        ServiceContext.current?.alerts?
            .success(.alert("Cursor configuration at \(.path(mcpConfigPath)) connected to the Tuist MCP server."))
    }
}
