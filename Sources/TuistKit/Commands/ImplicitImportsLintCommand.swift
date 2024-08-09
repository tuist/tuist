import ArgumentParser
import Path
import TuistLoader
import TuistSupport

struct LintImplicitImportsCommand: AsyncParsableCommand {
    init() {}
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "implicit-imports",
            abstract: "Find implicit imports in project"
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
        try await LintImplicitImportsService()
            .run(path: path)
    }
}
