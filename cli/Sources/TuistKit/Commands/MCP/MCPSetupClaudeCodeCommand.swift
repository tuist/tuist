import ArgumentParser
import Foundation

struct MCPSetupClaudeCodeCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "claude-code",
            abstract: "Setup Claude Code to use Tuist's MCP server"
        )
    }

    func run() async throws {
        let service = MCPSetupClaudeCodeCommandService()
        try await service.run()
    }
}
