import ArgumentParser
import Foundation

struct MCPSetupZedCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "zed",
            abstract: "Setup Zed editor to use Tuist's MCP server"
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
        help: "Configure Zed globally instead of locally."
    )
    var global: Bool = false

    func run() async throws {
        let service = MCPSetupZedCommandService()
        try await service.run(path: path, global: global)
    }
}
