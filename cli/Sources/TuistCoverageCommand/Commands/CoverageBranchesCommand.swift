import ArgumentParser
import Foundation
import TuistNooraExtension

public struct CoverageBranchesCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "branches",
            _superCommandName: "coverage",
            abstract: "List the branches with code coverage, the default branch first."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the Tuist project.",
        completion: .directory
    )
    var path: String?

    @Option(
        help: "The full handle of the project (account-handle/project-handle). Defaults to the one in the project's configuration."
    )
    var fullHandle: String?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await CoverageBranchesCommandService().run(path: path, fullHandle: fullHandle, json: json)
    }
}
