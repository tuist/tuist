import AnyCodable
import ArgumentParser
import Foundation
import GraphViz
import Path
import TuistGenerator
import TuistLoader
import TuistSupport
import XcodeGraph

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
        try await ImportFinderService().run(
            path: path.map { try AbsolutePath(validating: $0) } ?? FileHandler.shared.currentPath,
            targetName: targetName ?? "Unknown"
        )
    }
}
