import ArgumentParser
import Foundation

struct MCPSetupCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "setup",
            abstract: "Commands to automate integrating clients with Tuist's MCP server",
            subcommands: [
                MCPSetupClaudeCommand.self,
            ]
        )
    }
}
