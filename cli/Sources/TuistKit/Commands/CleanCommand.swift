import ArgumentParser
import Foundation
import TuistCore

public struct CleanCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "clean",
            abstract: "Clean all the artifacts stored locally"
        )
    }

    @Argument(
        help: "The cache and artifact categories to be cleaned. If no category is specified, everything is cleaned.",
        envKey: .cleanCleanCategories
    )
    var cleanCategories: [TuistCleanCategory] = TuistCleanCategory.allCases.map { $0 }

    @Flag(
        help: "Clean the remote cache",
        envKey: .cleanRemote
    )
    var remote: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project that should be cleaned.",
        completion: .directory,
        envKey: .cleanPath
    )
    var path: String?

    public func run() async throws {
        try await CleanService().run(
            categories: cleanCategories,
            remote: remote,
            path: path
        )
    }
}
