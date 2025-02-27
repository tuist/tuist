import ArgumentParser
import Foundation
import XcodeGraph

public struct MCPCommand: AsyncParsableCommand, TrackableParsableCommand {
    public var analyticsRequired: Bool { false }

    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "mcp",
            abstract: "Start an MCP server to interface LLMs with your local dev environment."
        )
    }

    public func run() async throws {}
}
