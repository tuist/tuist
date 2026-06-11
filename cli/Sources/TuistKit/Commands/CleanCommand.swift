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
    var cleanCategories: [TuistCleanCategory] = []

    @Option(
        name: [.customShort("e"), .customLong("exclude")],
        parsing: .upToNextOption,
        help: "The cache and artifact categories to exclude from cleaning. Cannot be combined with category arguments."
    )
    var excludedCategories: [TuistCleanCategory] = []

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

    var categoriesToClean: [TuistCleanCategory] {
        let includedCategories = cleanCategories.isEmpty ? TuistCleanCategory.allCases : cleanCategories
        return includedCategories.filter { !excludedCategories.contains($0) }
    }

    public func validate() throws {
        if !cleanCategories.isEmpty, !excludedCategories.isEmpty {
            throw ValidationError("Cannot use category arguments and --exclude at the same time.")
        }
    }

    public func run() async throws {
        try await CleanService().run(
            categories: categoriesToClean,
            remote: remote,
            path: path
        )
    }
}
