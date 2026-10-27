import ArgumentParser
import Foundation
import Path
import TuistEnvironment

public struct MigrationTargetsByDependenciesCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list-targets",
            _superCommandName: "migration",
            abstract: "It lists the targets of a project sorted by number of dependencies."
        )
    }

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the Xcode project",
        completion: .directory,
        envKey: .migrationListTargetsXcodeprojPath
    )
    var xcodeprojPath: String

    public func run() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        try await MigrationTargetsByDependenciesService()
            .run(xcodeprojPath: try AbsolutePath(validating: xcodeprojPath, relativeTo: cwd))
    }
}
