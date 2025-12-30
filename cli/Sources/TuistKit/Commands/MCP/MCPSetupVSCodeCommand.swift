import ArgumentParser
import Foundation

struct MCPSetupVSCodeCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "vscode",
            abstract: "Setup VS Code to use Tuist's MCP server"
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
        help: "Configure VS Code globally instead of locally."
    )
    var global: Bool = false

    func run() async throws {
        let service = MCPSetupVSCodeCommandService()
        try await service.run(path: path, global: global)
    }
}
