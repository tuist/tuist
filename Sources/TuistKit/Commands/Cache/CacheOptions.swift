import ArgumentParser
import Foundation

struct CacheOptions: ParsableArguments {
    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: [.customShort("P"), .long],
        help: "The name of the profile to be used when warming up the cache."
    )
    var profile: String?

    @Flag(
        name: [.customShort("x"), .long],
        help: "When passed it caches the targets for simulator and device using xcframeworks."
    )
    var xcframeworks: Bool = false
}
