import ArgumentParser
import Foundation

struct GenerateCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "generate",
                             abstract: "Generates an Xcode workspace to start working on the project.",
                             subcommands: [])
    }

    @Option(
        name: .shortAndLong,
        help: "The path where the project will be generated.",
        completion: .directory
    )
    var path: String?

    @Flag(
        help: "Only generate the local project (without generating its dependencies)."
    )
    var projectOnly: Bool = false

    @Flag(help: "Generate a project replacing dependencies with pre-compiled assets.")
    var cache: Bool = false

    func run() throws {
        try GenerateService().run(path: path,
                                  projectOnly: projectOnly,
                                  cache: cache)
    }
}
