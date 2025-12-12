import ArgumentParser
import TuistSupport

struct InspectImplicitImportsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "implicit-imports",
            abstract: "Find implicit imports in Tuist projects failing when cases are found. DEPRECATED: Use 'inspect dependencies --only implicit' instead.",
            shouldDisplay: false
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory,
        envKey: .lintImplicitDependenciesPath
    )
    var path: String?

    func run() async throws {
        Logger.current.warning(
            "The 'inspect implicit-imports' command is deprecated. Use 'inspect dependencies --only implicit' instead."
        )

        try await InspectDependenciesService()
            .run(path: path, inspectionTypes: [.implicit])
    }
}
