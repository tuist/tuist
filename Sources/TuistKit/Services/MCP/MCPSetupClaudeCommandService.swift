import FileSystem
import Foundation
import Path
import ServiceContextModule
import SwiftyJSON
import TuistSupport

struct MCPSetupClaudeCommandService {
    private let fileSystem: FileSystem
    private let configurationFileController: MCPConfigurationFileControlling

    init() {
        self.init(fileSystem: FileSystem(), configurationFileController: MCPConfigurationFileController())
    }

    init(fileSystem: FileSystem, configurationFileController: MCPConfigurationFileControlling) {
        self.fileSystem = fileSystem
        self.configurationFileController = configurationFileController
    }

    func run() async throws {
        try await configurationFileController.update(at: try AbsolutePath(validating: NSHomeDirectory()).appending(components: [
            "Library",
            "Application Support",
            "Claude",
            "claude_desktop_config.json",
        ]))
        ServiceContext.current?.alerts?.success(.alert("Claude configured to point to the Tuist's MCP server.", nextSteps: [
            "Restart the Claude app if it was opened",
            "Check out Claude's \(.link(title: "documentation", href: "https://modelcontextprotocol.io/quickstart/user"))",
        ]))
    }
}
