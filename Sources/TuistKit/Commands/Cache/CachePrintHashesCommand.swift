import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CachePrintHashesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "print-hashes",
                             abstract: "Print the hashes of the cacheable frameworks in the given project.")
    }

    @OptionGroup()
    var options: CacheOptions

    func run() throws {
        try CachePrintHashesService().run(
            path: options.path.map { AbsolutePath($0) } ?? FileHandler.shared.currentPath,
            xcframeworks: options.xcframeworks,
            profile: options.profile
        )
    }
}
