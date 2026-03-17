import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct BundleArtifactListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists artifacts for a bundle."
        )
    }

    @Argument(help: "The ID of the bundle.")
    var bundleId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(name: .shortAndLong, help: "The path to the directory or a subdirectory of the project.", completion: .directory)
    var path: String?

    @Option(
        name: .long,
        help: "The number of artifacts per page. Defaults to 50."
    )
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BundleArtifactListCommandService().run(
            bundleId: bundleId,
            fullHandle: project,
            path: path,
            pageSize: pageSize,
            json: json
        )
    }
}
