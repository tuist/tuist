import FileSystem
import Foundation
import Path
import TuistSupport

struct MCPSetupZedCommandService {
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
            // Global Zed settings location
            configPath = Environment.current.homeDirectory.appending(components: [
                ".config",
                "zed",
                "settings.json",
            ])
        } else {
            // Local Zed settings in workspace
            let basePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
            configPath = basePath.appending(components: [".zed", "settings.json"])
        }

        try await configurationFileController.update(
            for: .zed,
            at: configPath
        )

        let location = global ? "globally" : "locally at \(configPath.parentDirectory.pathString)"
        AlertController.current.success(.alert("Zed editor configured \(location) to point to Tuist's MCP server.", takeaways: [
            "Restart Zed editor if it was opened",
            "Check out the MCP \(.link(title: "documentation", href: "https://modelcontextprotocol.io/quickstart/user"))",
        ]))
    }
}
