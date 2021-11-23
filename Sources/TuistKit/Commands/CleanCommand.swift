import ArgumentParser
import Foundation
import TuistCore

/// Category that can be cleaned
enum CleanCategory: ExpressibleByArgument {
    static let allCases = CacheCategory.allCases.map { .global($0) } + [Self.dependencies]

    /// The global cache
    case global(CacheCategory)

    /// The local dependencies cache
    case dependencies

    var defaultValueDescription: String {
        switch self {
        case let .global(cacheCategory):
            return cacheCategory.rawValue
        case .dependencies:
            return "dependencies"
        }
    }

    init?(argument: String) {
        if let cacheCategory = CacheCategory(rawValue: argument) {
            self = .global(cacheCategory)
        } else if argument == "dependencies" {
            self = .dependencies
        } else {
            return nil
        }
    }
}

struct CleanCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "clean",
            abstract: "Clean all the artifacts stored locally"
        )
    }

    @Argument(help: "The cache and artifact categories to be cleaned. If no category is specified, everything is cleaned.")
    var cleanCategories: [CleanCategory] = CleanCategory.allCases

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project that should be cleaned.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try CleanService().run(
            categories: cleanCategories,
            path: path
        )
    }
}
