import ArgumentParser
import TuistAlert
import TuistSupport

struct InspectRedundantImportsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "redundant-imports",
            abstract: "Find redundant imports in Tuist projects failing when cases are found.",
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
        AlertController.current
            .warning(
                .alert(
                    "The 'tuist inspect redundant-imports' command is deprecated. Use 'tuist inspect dependencies --only redundant' instead."
                )
            )

        try await InspectDependenciesCommandService()
            .run(path: path, inspectionTypes: [.redundant])
    }
}
