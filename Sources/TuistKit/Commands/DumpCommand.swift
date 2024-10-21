import ArgumentParser
import Foundation
import Path
import TuistLoader
import TuistSupport

public struct DumpCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "dump",
            abstract: "Outputs the manifest as a JSON"
        )
    }

    // MARK: - Attributes

    @Option(
        name: .shortAndLong,
        help: "The path to the folder where the manifest is",
        completion: .directory,
        envKey: .dumpPath
    )
    var path: String?

    @Argument(help: "The manifest to be dumped", envKey: .dumpManifest)
    var manifest: DumpableManifest = .project

    public func run() async throws {
        try await DumpService().run(path: path, manifest: manifest)
    }
}

extension DumpableManifest: ExpressibleByArgument {}
