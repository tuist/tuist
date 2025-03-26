import ArgumentParser
import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistSupport

struct MCPSetupCursorCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cursor",
            abstract: "Configure a project's Cursor configuration to connect to the Tuist's MCP server.",
            subcommands: [
            ]
        )
    }

    @Option(
        name: .long,
        help: "The path to the directory where the cursor configuration will be written at \".cursor/mcp.json\". When absent, it uses the current working directory.",
        completion: .directory
    )
    var path: String?

    public func run() async throws {
        let currentWorkingDirectory = try await FileSystem().currentWorkingDirectory()
        let directory = try path
            .map { try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory) } ?? currentWorkingDirectory
        try await MCPSetupCursorCommandService().run(directory: directory)
    }
}
