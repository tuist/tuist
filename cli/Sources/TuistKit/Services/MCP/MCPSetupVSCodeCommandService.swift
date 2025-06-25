import FileSystem
import Foundation
import Path
import TuistSupport

struct MCPSetupVSCodeCommandService {
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
            // Global VS Code settings location
            #if os(macOS)
                configPath = Environment.current.homeDirectory.appending(components: [
                    "Library",
                    "Application Support",
                    "Code",
                    "User",
                    "settings.json",
                ])
            #elseif os(Linux)
                configPath = Environment.current.homeDirectory.appending(components: [
                    ".config",
                    "Code",
                    "User",
                    "settings.json",
                ])
            #else
                configPath = Environment.current.homeDirectory.appending(components: [
                    "AppData",
                    "Roaming",
                    "Code",
                    "User",
                    "settings.json",
                ])
            #endif
        } else {
            // Local VS Code settings in workspace
            let basePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
            configPath = basePath.appending(components: [".vscode", "settings.json"])
        }

        try await configurationFileController.update(
            for: .vscode,
            at: configPath
        )

        let location = global ? "globally" : "locally at \(configPath.parentDirectory.pathString)"
        AlertController.current.success(.alert("VS Code configured \(location) to point to Tuist's MCP server.", takeaways: [
            "Restart VS Code if it was opened",
            "Install the MCP extension if not already installed",
            "Check out the MCP \(.link(title: "documentation", href: "https://modelcontextprotocol.io/quickstart/user"))",
        ]))
    }
}
