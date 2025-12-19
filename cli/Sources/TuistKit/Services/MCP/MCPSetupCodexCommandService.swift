import FileSystem
import Foundation
import Path
import TuistSupport

struct MCPSetupCodexCommandService {
    private let fileSystem: FileSystem
    private let configurationFileController: MCPCodexConfigurationFileControlling

    init() {
        self.init(fileSystem: FileSystem(), configurationFileController: MCPCodexConfigurationFileController())
    }

    init(fileSystem: FileSystem, configurationFileController: MCPCodexConfigurationFileControlling) {
        self.fileSystem = fileSystem
        self.configurationFileController = configurationFileController
    }

    func run(path: String? = nil) async throws {
        let configPath: AbsolutePath

        if let path {
            let basePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
            configPath = basePath.appending(component: "config.toml")
        } else {
            configPath = Environment.current.homeDirectory.appending(components: [
                ".codex",
                "config.toml",
            ])
        }

        try await configurationFileController.update(at: configPath)

        let location = "at \(configPath.pathString)"
        AlertController.current.success(.alert("Codex configured \(location) to point to Tuist's MCP server.", takeaways: [
            "Restart Codex CLI if it was running",
            "Check out Codex's \(.link(title: "MCP configuration docs", href: "https://github.com/openai/codex/blob/main/docs/config.md#mcp-integration"))",
        ]))
    }
}

