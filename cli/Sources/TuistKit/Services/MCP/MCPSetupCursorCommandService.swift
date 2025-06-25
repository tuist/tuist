import FileSystem
import Foundation
import Path
import TuistSupport

struct MCPSetupCursorCommandService {
    private let fileSystem: FileSystem
    private let configurationFileController: MCPClientConfigurationControlling

    init() {
        self.init(fileSystem: FileSystem(), configurationFileController: MCPClientConfigurationController())
    }

    init(fileSystem: FileSystem, configurationFileController: MCPClientConfigurationControlling) {
        self.fileSystem = fileSystem
        self.configurationFileController = configurationFileController
    }

    func run(path: String? = nil, global: Bool = false) async throws {
        let configPath: AbsolutePath

        if global {
            // Global Cursor settings location
            configPath = Environment.current.homeDirectory.appending(components: [
                ".cursor",
                "settings.json",
            ])
        } else {
            // Local Cursor settings in workspace
            let basePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
            configPath = basePath.appending(components: [".cursor", "settings.json"])
        }

        try await configurationFileController.update(
            for: .cursor,
            at: configPath
        )

        let location = global ? "globally" : "locally at \(configPath.parentDirectory.pathString)"
        AlertController.current.success(.alert("Cursor IDE configured \(location) to point to Tuist's MCP server.", takeaways: [
            "Restart Cursor IDE if it was opened",
            "Check out the MCP \(.link(title: "documentation", href: "https://modelcontextprotocol.io/quickstart/user"))",
        ]))
    }
}
