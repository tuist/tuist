import ArgumentParser

struct MCPCommand: AsyncParsableCommand, TrackableParsableCommand {
    var analyticsRequired: Bool { false }

    init() {}

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "mcp",
            abstract: "Commands for interfacing with Tuist's MCP server",
            subcommands: [
                MCPStartCommand.self,
                MCPSetupCommand.self,
            ]
        )
    }
}
