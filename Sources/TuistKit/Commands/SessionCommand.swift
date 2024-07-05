import ArgumentParser
import Foundation
import Path

struct SessionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "session",
            abstract: "Prints the current Tuist session"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .sessionPath
    )
    var path: String?

    func run() throws {
        try SessionService().printSession(
            directory: path
        )
    }
}
