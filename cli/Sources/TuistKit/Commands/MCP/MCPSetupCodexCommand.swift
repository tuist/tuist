import ArgumentParser
import Foundation

struct MCPSetupCodexCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "codex",
            abstract: "Setup Codex CLI to use Tuist's MCP server"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory where the configuration should be created.",
        completion: .directory
    )
    var path: String?

    func run() async throws {
        try await MCPSetupCodexCommandService().run(path: path)
    }
}

