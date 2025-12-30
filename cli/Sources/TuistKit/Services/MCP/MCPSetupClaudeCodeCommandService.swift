import FileSystem
import Foundation
import Path
import TuistSupport

struct MCPSetupClaudeCodeCommandService {
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
            for: .claudeCode,
            at: Environment.current.homeDirectory.appending(components: [
                "Library",
                "Application Support",
                "Claude",
                "claude_desktop_config.json",
            ])
        )
        AlertController.current.success(.alert("Claude Code configured to point to Tuist's MCP server.", takeaways: [
            "Restart Claude Code if it was opened",
            "Use `/mcp` command to check server status",
            "Check out the MCP \(.link(title: "documentation", href: "https://docs.anthropic.com/en/docs/claude-code/mcp"))",
        ]))
    }
}
