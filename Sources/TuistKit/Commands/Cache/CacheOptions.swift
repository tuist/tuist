import ArgumentParser
import Foundation
import TuistCore

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

    @Option(
        name: .long,
        help: "Output type of xcframeworks when --xcframeworks is passed (device/simulator)",
        completion: .list(["device", "simulator"])
    )
    var destination: CacheXCFrameworkDestination = [.device, .simulator]
}

extension CacheXCFrameworkDestination: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "device":
            self = .device
        case "simulator":
            self = .simulator
        default:
            self = [.device, .simulator]
        }
    }
}
