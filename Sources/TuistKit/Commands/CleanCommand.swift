import ArgumentParser
import Foundation
import TuistCore

struct CleanCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "clean",
            abstract: "Clean all the artifacts stored locally"
        )
    }

    @Argument(help: "The cache categories to be cleaned. If no category is specified, the whole cache is cleaned.")
    var cacheCategories: [CacheCategory] = CacheCategory.allCases

    func run() throws {
        try CleanService().run(categories: cacheCategories)
    }
}

extension CacheCategory: ExpressibleByArgument {}
