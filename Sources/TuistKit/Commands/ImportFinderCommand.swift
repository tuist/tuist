import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistCore
import TuistLoader
import TuistSupport

public struct ImportFinderCommand: AsyncParsableCommand {
    public init() {}

    public var runId = UUID().uuidString

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "import_finder",
            abstract: "Find imports in target"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory,
        envKey: .graphPath
    )
    var path: String?

    @Option(
        name: [.customShort("t"), .long],
        help: "Target name to find imports"
    )
    var targetName: String?

    public func run() async throws {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let (graph, _, _) = try await manifestGraphLoader
            .load(path: path.map { try AbsolutePath(validating: $0) } ?? FileHandler.shared.currentPath)
        for (target, element) in try await GraphImplicitImportLintService(graph: graph).lint() {
            print(target.name)
            print(element)
        }
    }
}
