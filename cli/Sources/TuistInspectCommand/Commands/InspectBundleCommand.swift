import ArgumentParser
import FileSystem
import Foundation
import Path
import TuistEnvKey

public struct InspectBundleCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bundle",
            abstract: "Inspects an app bundle. The app bundle has to be either `.app`, `.xcarchive`, `.ipa`, `.aab`, or `.apk`."
        )
    }

    @Argument(
        help: "The path to the bundle.",
        completion: .directory,
        envKey: .inspectBundle
    )
    var bundle: String

    @Flag(
        help: "The output in JSON format.",
        envKey: .inspectBundleJSON
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project associated with the inspected bundle.",
        completion: .directory,
        envKey: .inspectBundlePath
    )
    var path: String?

    public func run() async throws {
        try await InspectBundleCommandService()
            .run(
                path: path,
                bundle: bundle,
                json: json
            )
    }
}
