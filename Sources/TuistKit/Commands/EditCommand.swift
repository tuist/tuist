import ArgumentParser
import Foundation
import Signals
import TSCBasic
import TuistGenerator
import TuistSupport

struct EditCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "edit",
                             abstract: "Generates a temporary project to edit the project in the current directory")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory whose project will be edited"
    )
    var path: String?

    @Flag(
        name: [.long, .customShort("P")],
        help: "It creates the project in the current directory or the one indicated by -p and doesn't block the process"
    )
    var permanent: Bool

    func run() throws {
        try EditService().run(path: path,
                              permanent: permanent)
    }
}
