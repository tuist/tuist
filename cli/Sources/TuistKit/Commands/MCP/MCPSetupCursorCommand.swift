import ArgumentParser
import Foundation

struct MCPSetupCursorCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cursor",
            abstract: "Setup Cursor IDE to use Tuist's MCP server"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory where the configuration should be created.",
        completion: .directory
    )
    var path: String?

    @Flag(
        name: .long,
        help: "Configure Cursor globally instead of locally."
    )
    var global: Bool = false

    func run() async throws {
        let service = MCPSetupCursorCommandService()
        try await service.run(path: path, global: global)
    }
}
