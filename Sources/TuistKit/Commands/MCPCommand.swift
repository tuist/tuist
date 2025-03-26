import ArgumentParser

public struct MCPCommand: AsyncParsableCommand, TrackableParsableCommand {
    public var analyticsRequired: Bool { false }

    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "mcp",
            abstract: "Start an MCP server to interface LLMs with your local dev environment.",
            subcommands: [
                MCPSetupCommand.self,
            ]
        )
    }

    public func run() async throws {
        try await MCPCommandService().run()
    }
}
