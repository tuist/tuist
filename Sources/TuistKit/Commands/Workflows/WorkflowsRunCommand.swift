import ArgumentParser
import Foundation

struct WorkflowsRunCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "workflows",
            _superCommandName: "run",
            abstract: "Runs a workflow with the given name. The name of the workflow is the name of the file without the extension."
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
