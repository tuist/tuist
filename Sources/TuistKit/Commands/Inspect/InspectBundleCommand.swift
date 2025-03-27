import ArgumentParser
import Foundation

struct InspectBundleCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bundle",
            abstract: "Inspects an app bundle. The app bundle has to be either `.app`, `.xcarchive` or `.ipa`."
        )
    }

    @Argument(
        help: "The path to the bundle.",
        completion: .directory,
        envKey: .inspectBundlePath
    )
    var path: String

    @Flag(
        help: "The output in JSON format.",
        envKey: .inspectBundleJSON
    )
    var json: Bool = false

    func run() async throws {
        try await InspectBundleCommandService()
            .run(
                path: path,
                json: json
            )
    }
}
