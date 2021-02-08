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

    @OptionGroup()
    var options: CacheOptions

    func run() throws {
        try CacheWarmService().run(path: options.path, profile: options.profile, xcframeworks: options.xcframeworks)
    }
}
