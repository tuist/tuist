import ArgumentParser
import TuistSupport

struct InspectImplicitImportsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "implicit-imports",
            abstract: "Find implicit imports in Tuist projects failing when cases are found."
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
        try await InspectImplicitImportsService()
            .run(path: path)
    }
}
