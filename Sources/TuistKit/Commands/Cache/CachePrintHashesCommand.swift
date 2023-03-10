import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CachePrintHashesCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "print-hashes",
            _superCommandName: "cache",
            abstract: "Print the hashes of the cacheable frameworks in the given project."
        )
    }

    @OptionGroup()
    var options: CacheOptions

    func run() async throws {
        try await CachePrintHashesService().run(
            path: options.path,
            xcframeworks: options.xcframeworks,
            destination: options.destination,
            profile: options.profile
        )
    }
}
