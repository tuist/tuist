import ArgumentParser
import Foundation

struct NamespaceCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "namespace",
            abstract: "Generates namespace files for your project.",
            subcommands: []
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path where the project for which we want to generate namespace is located."
    )
    var path: String?

    func run() throws {
        try NamespaceService().run(
            path: path
        )
    }
}
