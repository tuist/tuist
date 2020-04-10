import ArgumentParser
import Basic
import Foundation
import TuistLoader
import TuistSupport

struct DumpCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "dump",
                             abstract: "Outputs the project manifest as a JSON")
    }

    // MARK: - Attributes

    @Option(
        name: .shortAndLong,
        help: "The path to the folder where the project manifest is"
    )
    var path: String?

    func run() throws {
        try DumpService().run(path: path)
    }
}
