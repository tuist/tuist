import ArgumentParser
import Foundation
import TuistHasher
import TuistSupport

/// A command to hash an Xcode or generated project.
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

    @Argument(
        parsing: .captureForPassthrough,
        help: "When running tests selectively through 'tuist xcodebuild test', the additional 'xcodebuild' arguments that you'd pass, some of which are hashed."
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        try await HashSelectiveTestingCommandService(selectiveTestingGraphHasher: Extension.selectiveTestingGraphHasher).run(
            path: path,
            passthroughXcodebuildArguments: passthroughXcodebuildArguments
        )
    }
}
