import ArgumentParser
import TuistSupport

struct WorkflowsRunCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "Runs a workflow with the given name."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that will be used as working directory when running the workflow",
        completion: .directory,
        envKey: .lintImplicitDependenciesPath
    )
    var path: String?

    func run() async throws {

    }
}
