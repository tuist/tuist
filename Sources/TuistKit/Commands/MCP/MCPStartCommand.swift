import ArgumentParser

struct MCPStartCommand: AsyncParsableCommand, TrackableParsableCommand {
    var analyticsRequired: Bool { false }

    init() {}

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "start",
            abstract: "Start an MCP server to interface LLMs with your local dev environment.",
            shouldDisplay: false
        )
    }

    func run() async throws {
        try await MCPCommandService().run()
    }
}
