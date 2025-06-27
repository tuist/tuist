import FileSystem
import Foundation
import Path
import SwiftyJSON
import TuistSupport

struct MCPSetupClaudeCommandService {
    private let fileSystem: FileSystem
    private let configurationFileController: MCPClientConfigurationControlling

    init() {
        self.init(fileSystem: FileSystem(), configurationFileController: MCPClientConfigurationController())
    }

    init(fileSystem: FileSystem, configurationFileController: MCPClientConfigurationControlling) {
        self.fileSystem = fileSystem
        self.configurationFileController = configurationFileController
    }

    func run() async throws {
        try await configurationFileController.update(
            for: .claude,
            at: Environment.current.homeDirectory.appending(components: [
                "Library",
                "Application Support",
                "Claude",
                "claude_desktop_config.json",
            ])
        )
        AlertController.current.success(.alert("Claude configured to point to the Tuist's MCP server.", takeaways: [
            "Restart the Claude app if it was opened",
            "Check out Claude's \(.link(title: "documentation", href: "https://modelcontextprotocol.io/quickstart/user"))",
        ]))
    }
}
