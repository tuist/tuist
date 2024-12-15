import ArgumentParser
import TuistSupport

struct InspectRedundantImportsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "redundant-imports",
            abstract: "Find redundant imports in Tuist projects failing when cases are found."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory,
        envKey: .lintRedundantDependenciesPath
    )
    var path: String?

    func run() async throws {
        try await InspectRedundantImportsService()
            .run(path: path)
    }
}
