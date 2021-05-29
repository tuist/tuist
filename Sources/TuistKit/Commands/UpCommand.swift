import ArgumentParser
import Foundation

/// Command that configures the environment to work on the project.
struct UpCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "up",
            abstract: "Configures the environment for the project.",
            subcommands: []
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try UpService().run(path: path)
    }
}
