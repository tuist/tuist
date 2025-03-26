import ArgumentParser
import Foundation

struct InspectBundleCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bundle",
            abstract: "Inspects an app bundle."
        )
    }

    // TODO: We should also take out the bundle from the derived data if a path is not specified
    @Argument(
        help: "The path to the bundle.",
        completion: .directory,
        envKey: .inspectBundlePath
    )
    var path: String

    func run() async throws {
        try await InspectBundleCommandService()
            .run(
                path: path
            )
    }
}
