import ArgumentParser
import TuistSupport

struct InspectImplicitImportsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "implicit-imports",
            abstract: "Find implicit imports in Tuist projects failing when cases are found.",
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
        AlertController.current
            .warning(
                .alert(
                    "The 'tuist inspect implicit-imports' command is deprecated. Use 'tuist inspect dependencies --only implicit' instead."
                )
            )

        try await InspectDependenciesCommandService()
            .run(path: path, inspectionTypes: [.implicit])
    }
}
