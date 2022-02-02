import ArgumentParser
import Foundation
import TSCBasic
import TuistGenerator
import TuistSupport

struct EditCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "edit",
            abstract: "Generates a temporary project to edit the project in the current directory"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory whose project will be edited",
        completion: .directory
    )
    var path: String?

    @Flag(
        name: [.long, .customShort("P")],
        help: "It creates the project in the current directory or the one indicated by -p and doesn't block the process"
    )
    var permanent: Bool = false

    @Flag(
        name: [.long, .customShort("o")],
        help: "It only includes the manifest in the current directory."
    )
    var onlyCurrentDirectory: Bool = false

    func run() throws {
        try EditService().run(
            path: path,
            permanent: permanent,
            onlyCurrentDirectory: onlyCurrentDirectory
        )
    }
}
