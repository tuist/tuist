import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport

public struct ImplicitImportsLintCommand: AsyncParsableCommand {
    public init() {}

    public var runId = UUID().uuidString

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
        var projectPath = try path(path)
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let (graph, _, _, _) = try await manifestGraphLoader
            .load(path: projectPath)
        for (target, implicitDependencies) in try await GraphImplicitImportLintService(graph: graph).lint() {
            print("Target \(target.name) implicitly imports \(implicitDependencies.joined(separator: ", ")).")
        }
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
