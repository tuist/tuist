import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

public struct MigrationTargetsByDependenciesCommand: ParsableCommand {
    // MARK: - Configuration

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list-targets",
            _superCommandName: "migration",
            abstract: "It lists the targets of a project sorted by number of dependencies."
        )
    }

    // MARK: - Arguments & Flags

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the Xcode project",
        completion: .directory
    )
    var xcodeprojPath: String

    // MARK: - Init

    public init() {}

    // MARK: - ParsableCommand

    public func run() throws {
        try MigrationTargetsByDependenciesService()
            .run(xcodeprojPath: try AbsolutePath(validating: xcodeprojPath, relativeTo: FileHandler.shared.currentPath))
    }
}
