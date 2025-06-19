import ArgumentParser
import Foundation
import TuistSupport

struct MCPSetupClaudeCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "claude",
            abstract: "Configure your environment's Claude application to point to the Tuist's MCP server."
        )
    }

    func run() async throws {
        try await MCPSetupClaudeCommandService().run()
    }
}
