import ArgumentParser
import Basic
import Foundation
import TuistSupport

/// Command to cache frameworks as .xcframeworks and speed up your and others' build times.
struct CacheCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "cache",
                             abstract: "Cache frameworks as .xcframeworks to speed up build times in generated projects")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose frameworks will be cached"
    )
    var path: String?

    func run() throws {
        try CacheService().run(path: path)
    }
}
