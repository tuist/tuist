import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command to cache frameworks as .xcframeworks and speed up your and others' build times.
struct CacheWarmCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "warm",
                             abstract: "Warms the local and remote cache.")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached",
        completion: .directory
    )
    var path: String?

    @Flag(
        name: [.customShort("x"), .long],
        help: "When passed it caches the targets also for simulator and device in a .xcframework"
    )
    var xcframeworks: Bool = false

    func run() throws {
        try CacheWarmService().run(path: path, xcframeworks: xcframeworks)
    }
}
