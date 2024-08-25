import ArgumentParser
import Path
import TuistLoader
import TuistSupport

struct LintImplicitImportsCommand: AsyncParsableCommand {
    init() {}
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "implicit-imports",
            abstract: "Find implicit imports in Tuist projects."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory,
        envKey: .lintImplicitDependenciesPath
    )
    var path: String?

    @Flag(
        name: .shortAndLong,
        help: "Format of output. Use it if you launch command from XCode Run Script phase.",
        envKey: .lintImplicitDependenciesXcode
    )
    var xcode: Bool = false

    @Flag(
        name: .shortAndLong,
        help: "Exit with non-zero status if any unused code is found",
        envKey: .lintImplicitDependenciesStrict
    )
    var strict: Bool = false

    func run() async throws {
        try await LintImplicitImportsService()
            .run(
                path: path,
                xcode: xcode,
                strict: strict
            )
    }
}
