import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command to cache targets as `.(xc)framework`s and speed up your and your peers' build times.
struct CacheWarmCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "warm",
            _superCommandName: "cache",
            abstract: "Warms the local and remote cache."
        )
    }

    @OptionGroup()
    var options: CacheOptions

    @Argument(help: """
    A list of targets to cache. \
    Those and their dependant targets will be cached. \
    If no target is specified, the project defined targets and their dependencies will be  cached.
    """)
    var targets: [String] = []

    @Flag(help: "If passed, the command doesn't cache the targets passed in the `--targets` argument, but only their dependencies")
    var dependenciesOnly: Bool = false

    func run() throws {
        try CacheWarmService().run(
            path: options.path,
            profile: options.profile,
            xcframeworks: options.xcframeworks,
            targets: Set(targets),
            dependenciesOnly: dependenciesOnly
        )
    }
}
