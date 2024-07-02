import ArgumentParser
import Foundation

public struct ShareCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "share",
            abstract: "Generate a link to share your app"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project with the target or scheme to be run.",
        completion: .directory
    )
    var path: String?

    public func run() async throws {
        try await ShareService().run(
            path: path,
            configuration: nil
        )
    }
}
