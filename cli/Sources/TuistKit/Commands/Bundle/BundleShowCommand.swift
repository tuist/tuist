import ArgumentParser
import Foundation
import TuistSupport

struct BundleShowCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            _superCommandName: "bundle",
            abstract: "Show details of a specific bundle."
        )
    }

    @Argument(help: "The ID of the bundle to show.")
    var bundleId: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .bundleShowPath
    )
    var path: String?

    func run() async throws {
        try await BundleShowService().run(
            bundleId: bundleId,
            directory: path
        )
    }
}