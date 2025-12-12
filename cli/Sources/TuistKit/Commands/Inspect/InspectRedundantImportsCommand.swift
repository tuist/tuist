import ArgumentParser
import TuistSupport

struct InspectRedundantImportsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "redundant-imports",
            abstract: "Find redundant imports in Tuist projects failing when cases are found. DEPRECATED: Use 'tuist inspect dependencies --only redundant' instead.",
            shouldDisplay: false
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
        Logger.current.warning("The 'tuist inspect redundant-imports' command is deprecated. Use 'tuist inspect dependencies --only redundant' instead.")

        try await InspectDependenciesService()
            .run(path: path, inspectionTypes: [.redundant])
    }
}
