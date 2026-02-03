import ArgumentParser
import Foundation
import TuistExtension
import TuistHasher
import TuistSupport

/// A command to hash a generated project.
public struct HashSelectiveTestingCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "selective-testing",
            _superCommandName: "hash",
            abstract: "Returns the hashes that will be used to persist targets' test results to select tests in future test runs."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose tests will run selectively.",
        completion: .directory,
        envKey: .hashCachePath
    )
    var path: String?

    public func run() async throws {
        try await HashSelectiveTestingCommandService(selectiveTestingGraphHasher: TuistKitExtension.selectiveTestingGraphHasher)
            .run(
                path: path
            )
    }
}
