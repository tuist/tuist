import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CachePrintHashesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "print-hashes",
                             abstract: "Print the hashes of the cacheable frameworks in the given project.")
    }

    @Option(
        name: .shortAndLong,
        help: "The path where the project will be generated.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: [.customShort("P"), .long],
        help: "The name of the cache profile."
    )
    var profile: String?

    @Flag(
        name: [.customShort("x"), .long],
        help: "When passed it caches the targets for simulator and device in a .xcframework"
    )
    var xcframeworks: Bool = false

    func run() throws {
        try CachePrintHashesService().run(path: path.map { AbsolutePath($0) } ?? FileHandler.shared.currentPath, xcframeworks: xcframeworks, profile: profile)
    }
}
