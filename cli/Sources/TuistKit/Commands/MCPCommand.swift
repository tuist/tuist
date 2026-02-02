#if os(macOS)
    import ArgumentParser

    public struct MCPCommand: AsyncParsableCommand, TrackableParsableCommand {
        public init() {}
        public var analyticsRequired: Bool { false }

        public static var configuration: CommandConfiguration {
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
#endif
