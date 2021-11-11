import ArgumentParser
import Foundation
import TuistCore

/// Category that can be cleaned
enum CleanCategory: String, CaseIterable, ExpressibleByArgument {
    /// The plugins cache.
    case plugins

    /// The build cache
    case builds

    /// The tests cache
    case tests

    /// The projects generated for automation tasks cache
    case generatedAutomationProjects

    /// The project description helpers cache
    case projectDescriptionHelpers

    /// The manifests cache
    case manifests
    
    /// The dependencies cache
    case dependencies
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
