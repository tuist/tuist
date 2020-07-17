import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command to cache frameworks as .xcframeworks and speed up your and others' build times.
struct ScaleWarmCacheCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "warm-cache",
                             abstract: "Warms the local and remote cache.")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose frameworks will be cached"
    )
    var path: String?

    func run() throws {
        try ScaleWarmCacheService().run(path: path)
    }
}
