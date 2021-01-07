import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command to cache targets as `.(xc)framework`s and speed up your and your peers' build times.
struct CacheWarmCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "warm",
                             abstract: "Warms the local and remote cache.")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "The name of the flavor to be used when warming up the cache."
    )
    var flavor: String?

    @Flag(
        name: [.customShort("x"), .long],
        help: "When passed it caches the targets for simulator and device using xcframeworks."
    )
    var xcframeworks: Bool = false

    func run() throws {
        try CacheWarmService().run(path: path, flavor: flavor, xcframeworks: xcframeworks)
    }
}
