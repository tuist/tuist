import ArgumentParser
import Foundation

struct WorkflowsLSCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "workflows",
            _superCommandName: "ls",
            abstract: "Lists the workflows that are available for running."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .authPath
    )
    var path: String?

    func run() async throws {
        // TODO
    }
}
