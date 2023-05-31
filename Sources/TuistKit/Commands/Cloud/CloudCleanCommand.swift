import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct CloudCleanCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "clean",
            _superCommandName: "cloud",
            abstract: "Cleans the remote cache."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the Tuist Cloud project.",
        completion: .directory
    )
    var path: String?

    func run() async throws {
        try await CloudCleanService().clean(
            path: path
        )
    }
}
