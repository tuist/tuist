import ArgumentParser
import Foundation

struct InspectBuildCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "Inspects the latest build."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to inspect the latest build for.",
        completion: .directory,
        envKey: .inspectBuildPath
    )
    var path: String?

    func run() async throws {
        try await InspectBuildCommandService()
            .run(
                path: path
            )
    }
}
