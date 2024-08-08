import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport

public struct ImplicitImportsLintCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "implicit-imports",
            abstract: "Find implicit imports in project"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory,
        envKey: .graphPath
    )
    var path: String?

    public func run() async throws {
        let projectPath = try path(path)
        try await ImplicitImportsLintService(
            graphImplicitLintService: GraphImplicitImportLintService(
                importSourceCodeScanner: ImportSourceCodeScanner()
            ),
            generatorFactory: GeneratorFactory(),
            configLoader: ConfigLoader()
        )
        .run(projectPath: projectPath)
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
