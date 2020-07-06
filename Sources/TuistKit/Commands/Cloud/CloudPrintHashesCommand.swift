import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudPrintHashesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "print-hashes",
                             abstract: "Print the hashes of the frameworks used by the given project.")
    }

    @Option(
        name: .shortAndLong,
        help: "The path where the project will be generated."
    )
    var path: String?

    func run() throws {
        try CloudPrintHashesService().run(path: path.map { AbsolutePath($0) } ?? FileHandler.shared.currentPath)
    }
}
