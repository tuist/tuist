import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command to cache frameworks as .xcframeworks and speed up your and others' build times.
struct CloudPopulateCacheCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "populate-cache",
                             abstract: "Populates the local cache and pushes it to the cloud (should only be used by CI)")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose frameworks will be cached"
    )
    var path: String?

    func run() throws {
        try CloudPopulateCacheService().run(path: path)
    }
}
